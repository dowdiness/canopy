///|
test "RuleBased + agreeing Guessed → Confirmed" {
  let a : Confidence[Role] = RuleBased(SectionIntro)
  let b : Confidence[Role] = Guessed(0.9F, SectionIntro)
  inspect(a.join(b), content="Confirmed(SectionIntro)")
}

///|
test "RuleBased + disagreeing Guessed → Conflict" {
  let a : Confidence[Role] = RuleBased(SectionIntro)
  let b : Confidence[Role] = Guessed(0.9F, Abstract)
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
  let a : Confidence[Role] = Guessed(0.3F, KeyPoints)
  let b : Confidence[Role] = Guessed(0.8F, KeyPoints)
  inspect(a.join(b), content="Guessed(0.800000011920929, KeyPoints)")
}

///|
test "Guessed with different values → Conflict" {
  let a : Confidence[Role] = Guessed(0.9F, Abstract)
  let b : Confidence[Role] = Guessed(0.1F, SectionIntro)
  inspect(a.join(b), content="Conflict")
}

///|
test "Unknown is identity (concrete)" {
  let a : Confidence[Role] = RuleBased(Abstract)
  inspect(Unknown.join(a), content="RuleBased(Abstract)")
  inspect(a.join(Unknown), content="RuleBased(Abstract)")
}
