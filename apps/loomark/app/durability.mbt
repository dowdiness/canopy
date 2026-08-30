///|
priv enum SaveEffect {
  NoSaveEffect
  ArmQuiet(Int, String)
  ArmQuietAndMaximum(Int, String)
  Persist(String)
}

///|
fn SaveState::pending_epoch(self : SaveState) -> Int? {
  match self {
    Waiting(checkpoint) => Some(checkpoint.epoch)
    Saving(_, Some(checkpoint)) => Some(checkpoint.epoch)
    Saved | Saving(_, None) | Failed(_, _) => None
  }
}

///|
fn Checkpoint::eligible(self : Checkpoint) -> Checkpoint {
  { ..self, eligibility: Eligible }
}

///|
fn allocate_checkpoint(editing : EditingState) -> (EditingState, Checkpoint) {
  let epoch = editing.last_checkpoint_epoch + 1
  (
    { ..editing, last_checkpoint_epoch: epoch },
    { epoch, eligibility: Deferred },
  )
}

///|
fn checkpoint_edit_effect(
  editing : EditingState,
  checkpoint : Checkpoint,
  text : String,
  new_epoch : Bool,
) -> SaveEffect {
  if editing.composing || checkpoint.eligibility == Eligible {
    NoSaveEffect
  } else if new_epoch {
    ArmQuietAndMaximum(checkpoint.epoch, text)
  } else {
    ArmQuiet(checkpoint.epoch, text)
  }
}

///|
fn text_equals_acknowledged(editing : EditingState, text : String) -> Bool {
  match editing.repository.source(editing.activation.document_id) {
    Some(source) => source.text() == text
    None => false
  }
}

///|
fn save_after_text_changed(
  editing : EditingState,
  text : String,
) -> (EditingState, SaveEffect) {
  match editing.save {
    Failed(failure, retry_after_composition) =>
      (
        { ..editing, text, save: Failed(failure, retry_after_composition) },
        NoSaveEffect,
      )
    Saving(candidate, pending) =>
      if text == candidate {
        ({ ..editing, text, save: Saving(candidate, None) }, NoSaveEffect)
      } else {
        match pending {
          Some(checkpoint) =>
            (
              { ..editing, text, save: Saving(candidate, Some(checkpoint)) },
              checkpoint_edit_effect(editing, checkpoint, text, false),
            )
          None => {
            let (editing, checkpoint) = allocate_checkpoint(editing)
            (
              { ..editing, text, save: Saving(candidate, Some(checkpoint)) },
              checkpoint_edit_effect(editing, checkpoint, text, true),
            )
          }
        }
      }
    Saved =>
      if text_equals_acknowledged(editing, text) {
        ({ ..editing, text, save: Saved }, NoSaveEffect)
      } else {
        let (editing, checkpoint) = allocate_checkpoint(editing)
        (
          { ..editing, text, save: Waiting(checkpoint) },
          checkpoint_edit_effect(editing, checkpoint, text, true),
        )
      }
    Waiting(checkpoint) =>
      if text_equals_acknowledged(editing, text) {
        ({ ..editing, text, save: Saved }, NoSaveEffect)
      } else {
        (
          { ..editing, text, save: Waiting(checkpoint) },
          checkpoint_edit_effect(editing, checkpoint, text, false),
        )
      }
  }
}

///|
fn save_after_eligible(
  editing : EditingState,
  epoch : Int,
) -> (EditingState, SaveEffect) {
  match editing.save {
    Waiting(checkpoint) if checkpoint.epoch == epoch => {
      let checkpoint = checkpoint.eligible()
      if editing.composing || editing.creation == Creating {
        ({ ..editing, save: Waiting(checkpoint) }, NoSaveEffect)
      } else {
        let candidate = editing.text
        ({ ..editing, save: Saving(candidate, None) }, Persist(candidate))
      }
    }
    Saving(candidate, Some(checkpoint)) if checkpoint.epoch == epoch =>
      (
        { ..editing, save: Saving(candidate, Some(checkpoint.eligible())) },
        NoSaveEffect,
      )
    Saved | Waiting(_) | Saving(_, _) | Failed(_, _) => (editing, NoSaveEffect)
  }
}

///|
fn save_after_composition_ended(
  editing : EditingState,
) -> (EditingState, SaveEffect) {
  let editing = { ..editing, composing: false }
  match editing.save {
    Waiting({ eligibility: Eligible, .. }) => {
      let candidate = editing.text
      ({ ..editing, save: Saving(candidate, None) }, Persist(candidate))
    }
    Waiting(checkpoint) =>
      (editing, ArmQuietAndMaximum(checkpoint.epoch, editing.text))
    Saving(_, None) | Saving(_, Some({ eligibility: Eligible, .. })) =>
      (editing, NoSaveEffect)
    Saving(_, Some(checkpoint)) =>
      (editing, ArmQuietAndMaximum(checkpoint.epoch, editing.text))
    Failed(_, false) | Saved => (editing, NoSaveEffect)
    Failed(_, true) => {
      let candidate = editing.text
      ({ ..editing, save: Saving(candidate, None) }, Persist(candidate))
    }
  }
}

///|
fn save_after_success(
  editing : EditingState,
  candidate : String,
  pending : Checkpoint?,
  repository : @source_repository.RepositorySnapshot,
) -> (EditingState, SaveEffect) {
  let completed = { ..editing, repository, }
  if candidate == editing.text {
    ({ ..completed, save: Saved }, NoSaveEffect)
  } else {
    match pending {
      Some(checkpoint) =>
        match checkpoint.eligibility {
          Deferred => ({ ..completed, save: Waiting(checkpoint) }, NoSaveEffect)
          Eligible =>
            if editing.composing || editing.creation == Creating {
              ({ ..completed, save: Waiting(checkpoint) }, NoSaveEffect)
            } else {
              let latest = editing.text
              ({ ..completed, save: Saving(latest, None) }, Persist(latest))
            }
        }
      None => {
        let (completed, checkpoint) = allocate_checkpoint(completed)
        let effect = if editing.composing || editing.creation == Creating {
          NoSaveEffect
        } else {
          ArmQuietAndMaximum(checkpoint.epoch, editing.text)
        }
        ({ ..completed, save: Waiting(checkpoint) }, effect)
      }
    }
  }
}

///|
fn save_after_failure(
  editing : EditingState,
  failure : @source_repository.SaveFailure,
) -> EditingState {
  { ..editing, save: Failed(failure, false) }
}

///|
fn save_after_retry(editing : EditingState) -> (EditingState, SaveEffect) {
  match editing.save {
    Failed(failure, _) if editing.composing =>
      ({ ..editing, save: Failed(failure, true) }, NoSaveEffect)
    Failed(_, _) => {
      let candidate = editing.text
      ({ ..editing, save: Saving(candidate, None) }, Persist(candidate))
    }
    Saved | Waiting(_) | Saving(_, _) => (editing, NoSaveEffect)
  }
}
