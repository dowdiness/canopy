///|
test "RuleBased + agreeing Guessed → Confirmed" {
  let a : Confidence[Role] = RuleBased(SectionIntro)
  let b : Confidence[Role] = Confidence::guessed(0.9F, SectionIntro)
  inspect(a.join(b), content="Confirmed(SectionIntro)")
}

///|
test "RuleBased + disagreeing Guessed → Conflict" {
  let a : Confidence[Role] = RuleBased(SectionIntro)
  let b : Confidence[Role] = Confidence::guessed(0.9F, Abstract)
  inspect(a.join(b), content="Conflict")
}

///|
test "Conflict absorbs everything" {
  let c : Confidence[Role] = Conflict
  inspect(c.join(RuleBased(Abstract)), content="Conflict")
  inspect(c.join(Unknown), content="Conflict")
  inspect(c.join(Confirmed(SectionIntro)), content="Conflict")
}

///|
test "Guessed picks higher confidence on equal values" {
  let a : Confidence[Role] = Confidence::guessed(0.3F, KeyPoints)
  let b : Confidence[Role] = Confidence::guessed(0.8F, KeyPoints)
  inspect(a.join(b), content="Guessed(0.800000011920929, KeyPoints)")
}

///|
test "Guessed with different values → Conflict" {
  let a : Confidence[Role] = Confidence::guessed(0.9F, Abstract)
  let b : Confidence[Role] = Confidence::guessed(0.1F, SectionIntro)
  inspect(a.join(b), content="Conflict")
}

///|
test "Unknown is identity (concrete)" {
  let a : Confidence[Role] = RuleBased(Abstract)
  inspect(Unknown.join(a), content="RuleBased(Abstract)")
  inspect(a.join(Unknown), content="RuleBased(Abstract)")
}

///|
test "guessed constructor accepts valid range" {
  inspect(Confidence::guessed(0.0F, Abstract), content="Guessed(0, Abstract)")
  inspect(Confidence::guessed(0.5F, Abstract), content="Guessed(0.5, Abstract)")
  inspect(Confidence::guessed(1.0F, Abstract), content="Guessed(1, Abstract)")
}

///|
test "guessed constructor rejects NaN" {
  let raised = try {
    let _ = Confidence::guessed(@float.not_a_number, Abstract)
    None
  } catch {
    BadConfidence(f) => Some(f)
  }
  guard raised is Some(f) else { fail("expected BadConfidence") }
  assert_true(f.is_nan())
}

///|
test "guessed constructor rejects infinity" {
  let raised = try {
    let _ = Confidence::guessed(@float.infinity, Abstract)
    None
  } catch {
    BadConfidence(f) => Some(f)
  }
  guard raised is Some(f) else { fail("expected BadConfidence") }
  assert_eq(f, @float.infinity)
}

///|
test "guessed constructor rejects negative" {
  let raised = try {
    let _ = Confidence::guessed(-0.1F, Abstract)
    None
  } catch {
    BadConfidence(f) => Some(f)
  }
  guard raised is Some(f) else { fail("expected BadConfidence") }
  assert_eq(f, -0.1F)
}

///|
test "guessed constructor rejects > 1" {
  let raised = try {
    let _ = Confidence::guessed(1.1F, Abstract)
    None
  } catch {
    BadConfidence(f) => Some(f)
  }
  guard raised is Some(f) else { fail("expected BadConfidence") }
  assert_eq(f, 1.1F)
}
