///|
pub(all) enum Editor {
  Ready
  Creating
  Importing
  ConfirmingDelete
}

///|
pub(all) enum Readiness {
  SignedOut(editor~ : Editor, durability~ : @documents.LocalDurability)
  EditorUnavailable
  CheckingAccount
  SignedIn
  AccountUnavailable
}

///|
pub enum Action {
  Begin
  Cancel(Int)
} derive(Eq)

///|
pub struct Request {
  priv serial : Int
} derive(Eq)

///|
pub(all) enum Event {
  Invoke(Action)
  AuthorizationReceived(Request, @account_http.GoogleAuthorizationUrl?)
  Interrupted
  Refresh
  PageRestored
  AuthenticationFailed
}

///|
pub enum Effect {
  SaveChanges
  RequestAuthorizationUrl(Request)
  Navigate(@account_http.GoogleAuthorizationUrl)
  FocusEditor
  CheckAccount
}

///|
pub enum Failure {
  Save(@documents.LocalSaveFailure)
  Authentication
} derive(Eq)

///|
pub enum View {
  Available(Action)
  Unavailable
  InProgress(Action)
  Failed(Failure, retry~ : Action?)
  Leaving
} derive(Eq)

///|
pub enum Outcome {
  Applied
  Unavailable
  Superseded
  RequestReleased
}

///|
pub enum SignIn {
  Idle(generation~ : Int, pending~ : Request?)
  SavingChanges(generation~ : Int, pending~ : Request?)
  Connecting(generation~ : Int, request~ : Request)
  RedirectPending(
    generation~ : Int,
    destination~ : @account_http.GoogleAuthorizationUrl
  )
  Leaving(generation~ : Int)
  SaveFailed(
    generation~ : Int,
    pending~ : Request?,
    failure~ : @documents.LocalSaveFailure
  )
  AuthenticationFailed(generation~ : Int, pending~ : Request?)
} derive(Eq)

///|
pub struct Transition {
  state : SignIn
  effects : Array[Effect]
  outcome : Outcome
}

///|
pub fn SignIn::SignIn() -> SignIn {
  Idle(generation=0, pending=None)
}

///|
fn SignIn::generation(self : Self) -> Int {
  match self {
    Idle(generation~, ..)
    | SavingChanges(generation~, ..)
    | Connecting(generation~, ..)
    | RedirectPending(generation~, ..)
    | Leaving(generation~)
    | SaveFailed(generation~, ..)
    | AuthenticationFailed(generation~, ..) => generation
  }
}

///|
fn SignIn::pending(self : Self) -> Request? {
  match self {
    Idle(pending~, ..)
    | SavingChanges(pending~, ..)
    | SaveFailed(pending~, ..)
    | AuthenticationFailed(pending~, ..) => pending
    Connecting(request~, ..) => Some(request)
    RedirectPending(..) | Leaving(..) => None
  }
}

///|
fn SignIn::transition(
  self : Self,
  outcome? : Outcome = Applied,
  effects? : Array[Effect] = [],
) -> Transition {
  { state: self, effects, outcome, }
}

///|
pub fn SignIn::blocks_editing(self : Self) -> Bool {
  match self {
    SavingChanges(..) | Connecting(..) | RedirectPending(..) | Leaving(..) =>
      true
    Idle(..) | SaveFailed(..) | AuthenticationFailed(..) => false
  }
}

///|
pub fn SignIn::view(self : Self, readiness : Readiness) -> View {
  let action = match readiness {
    SignedOut(editor=Ready, durability~) if !(durability
      is @documents.AwaitingInput) => Some(Action::Begin)
    _ => None
  }
  match self {
    SavingChanges(generation~, ..)
    | Connecting(generation~, ..)
    | RedirectPending(generation~, ..) => InProgress(Action::Cancel(generation))
    Leaving(..) => View::Leaving
    SaveFailed(failure~, ..) =>
      View::Failed(Failure::Save(failure), retry=action)
    AuthenticationFailed(..) => View::Failed(Authentication, retry=action)
    Idle(..) =>
      match action {
        Some(action) => Available(action)
        None => View::Unavailable
      }
  }
}

///|
fn SignIn::invoke(
  self : Self,
  action : Action,
  readiness : Readiness,
) -> Transition {
  match action {
    Begin =>
      match self {
        Idle(..) | SaveFailed(..) | AuthenticationFailed(..) =>
          match readiness {
            SignedOut(..) =>
              SavingChanges(
                generation=self.generation() + 1,
                pending=self.pending(),
              ).transition(effects=[SaveChanges])
            _ => self.transition(outcome=Outcome::Unavailable)
          }
        SavingChanges(..)
        | Connecting(..)
        | RedirectPending(..)
        | Leaving(..) => self.transition(outcome=Outcome::Superseded)
      }
    Cancel(observed) if observed != self.generation() =>
      self.transition(outcome=Outcome::Superseded)
    Cancel(_) =>
      match self {
        SavingChanges(..) | Connecting(..) | RedirectPending(..) =>
          Idle(generation=self.generation(), pending=self.pending()).transition(effects=[
              FocusEditor,
            ],
          )
        Idle(..) | SaveFailed(..) | AuthenticationFailed(..) | Leaving(..) =>
          self.transition(outcome=Outcome::Superseded)
      }
  }
}

///|
fn SignIn::receive(
  self : Self,
  request : Request,
  authorization_url : @account_http.GoogleAuthorizationUrl?,
  readiness : Readiness,
) -> Transition {
  match self {
    Connecting(generation~, request=current) if current == request =>
      match readiness {
        SignedIn | AccountUnavailable =>
          Idle(generation~, pending=None).transition(
            outcome=Outcome::RequestReleased,
          )
        SignedOut(..) | EditorUnavailable | CheckingAccount =>
          match authorization_url {
            Some(destination) =>
              RedirectPending(generation~, destination~).transition()
            None =>
              SignIn::AuthenticationFailed(generation~, pending=None).transition()
          }
      }
    Idle(generation~, pending=Some(current)) if current == request =>
      Idle(generation~, pending=None).transition(
        outcome=Outcome::RequestReleased,
      )
    SavingChanges(generation~, pending=Some(current)) if current == request =>
      SavingChanges(generation~, pending=None).transition(
        outcome=Outcome::RequestReleased,
      )
    SaveFailed(generation~, pending=Some(current), failure~) if current ==
      request =>
      SaveFailed(generation~, pending=None, failure~).transition(
        outcome=Outcome::RequestReleased,
      )
    AuthenticationFailed(generation~, pending=Some(current)) if current ==
      request =>
      SignIn::AuthenticationFailed(generation~, pending=None).transition(
        outcome=Outcome::RequestReleased,
      )
    _ => self.transition(outcome=Outcome::Superseded)
  }
}

///|
fn SignIn::advance(self : Self, readiness : Readiness) -> Transition {
  match (self, readiness) {
    (
      SavingChanges(..)
      | Connecting(..)
      | RedirectPending(..),
      SignedIn
      | AccountUnavailable,
    ) =>
      return Idle(generation=self.generation(), pending=self.pending()).transition()
    (_, CheckingAccount) => return self.transition()
    _ => ()
  }
  match self {
    Connecting(..) => self.transition()
    SavingChanges(generation~, pending~) =>
      match readiness {
        SignedOut(editor~, durability~) =>
          match editor {
            Creating | Importing => self.transition()
            Ready | ConfirmingDelete =>
              match durability {
                @documents.LocalDurability::AwaitingInput
                | @documents.LocalDurability::Saving => self.transition()
                @documents.LocalDurability::Failed(failure) =>
                  SaveFailed(generation~, pending~, failure~).transition()
                @documents.LocalDurability::Durable =>
                  match pending {
                    Some(request) =>
                      Connecting(generation~, request~).transition()
                    None => {
                      let request = Request::{ serial: generation, }
                      Connecting(generation~, request~).transition(effects=[
                        RequestAuthorizationUrl(request),
                      ])
                    }
                  }
              }
          }
        EditorUnavailable | CheckingAccount | SignedIn | AccountUnavailable =>
          self.transition()
      }
    RedirectPending(generation~, destination~) =>
      match readiness {
        SignedOut(editor~, durability~) =>
          match editor {
            Creating | Importing => self.transition()
            Ready | ConfirmingDelete =>
              match durability {
                @documents.LocalDurability::AwaitingInput
                | @documents.LocalDurability::Saving => self.transition()
                @documents.LocalDurability::Failed(failure) =>
                  SaveFailed(generation~, pending=None, failure~).transition()
                @documents.LocalDurability::Durable =>
                  SignIn::Leaving(generation~).transition(effects=[
                    Navigate(destination),
                  ])
              }
          }
        EditorUnavailable | CheckingAccount | SignedIn | AccountUnavailable =>
          self.transition()
      }
    Idle(..) | SaveFailed(..) | AuthenticationFailed(..) | Leaving(..) =>
      self.transition()
  }
}

///|
pub fn SignIn::update(
  self : Self,
  event : Event,
  readiness : Readiness,
) -> Transition {
  let result = match event {
    Invoke(action) => {
      let result = self.invoke(action, readiness)
      if result.effects is [SaveChanges] {
        return result
      }
      result
    }
    AuthorizationReceived(request, authorization_url) =>
      self.receive(request, authorization_url, readiness)
    Interrupted =>
      match self {
        SavingChanges(..) | Connecting(..) | RedirectPending(..) =>
          Idle(generation=self.generation(), pending=self.pending()).transition()
        Idle(..) | SaveFailed(..) | AuthenticationFailed(..) | Leaving(..) =>
          self.transition()
      }
    Refresh => self.transition()
    PageRestored =>
      match self {
        Leaving(generation~) =>
          return Idle(generation~, pending=None).transition(effects=[
            CheckAccount,
          ])
        _ => return self.transition()
      }
    AuthenticationFailed =>
      SignIn::AuthenticationFailed(
        generation=self.generation(),
        pending=self.pending(),
      ).transition()
  }
  let next = result.state.advance(readiness)
  {
    ..next,
    outcome: result.outcome,
    effects: if result.effects.is_empty() {
      next.effects
    } else if next.effects.is_empty() {
      result.effects
    } else {
      result.effects + next.effects
    },
  }
}

///|
pub extend SignIn with Eq::{equal, not_equal}

///|
pub extend View with Eq::{equal, not_equal}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Request with Eq::{equal, not_equal}

///|
pub extend Failure with Eq::{equal, not_equal}
