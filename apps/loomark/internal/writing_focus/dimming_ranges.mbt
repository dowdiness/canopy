///|
pub(all) enum OpacitySample {
  Still(Double)
  Animating(Double, ActiveFade)
}

///|
const UNFOCUSED_TEXT_OPACITY : Double = 0.5

///|
fn merge_settled_ranges(
  samples : ArrayView[(Range, OpacitySample)],
) -> ArrayView[(Range, OpacitySample)] {
  let ranges : Array[(Range, OpacitySample)] = samples.fold(init=[], (
    ranges,
    sample,
  ) => {
    let (range, opacity_sample) = sample
    match (ranges.last(), opacity_sample) {
      (_, Still(0.0)) => ranges
      (Some((previous_range, Still(previous_opacity))), Still(opacity)) if previous_range.end ==
        range.start &&
        previous_opacity == opacity => {
        ranges[ranges.length() - 1] = (
          { start: previous_range.start, end: range.end, },
          Still(opacity),
        )
        ranges
      }
      _ => {
        ranges.push(sample)
        ranges
      }
    }
  })
  ranges[:]
}

///|
pub fn calculate_dimming_ranges(
  focus_range : Range,
  previous : ArrayView[(Range, OpacitySample)],
  timeline_time_ms : Double?,
  animate~ : Bool,
) -> ArrayView[(Range, Fade)] {
  let previous = merge_settled_ranges(previous)
  let boundaries = previous.fold(
    init=[0.0, @double.infinity, focus_range.start, focus_range.end],
    (boundaries, sample) => {
      let (range, _) = sample
      boundaries.push(range.start)
      boundaries.push(range.end)
      boundaries
    },
  )
  boundaries.sort()
  boundaries.dedup()
  let ranges : Array[(Range, Fade)] = boundaries[:boundaries.length() - 1].foldi(
    init=[],
    (index, ranges, start) => {
      let end = boundaries[index + 1]
      let overlay_opacity = if start >= focus_range.start &&
        end <= focus_range.end {
        0.0
      } else {
        1.0 - UNFOCUSED_TEXT_OPACITY
      }
      let sample = match
        previous.binary_search_by(sample => {
          let (range, _) = sample
          if range.end <= start {
            -1
          } else if range.start > start {
            1
          } else {
            0
          }
        }) {
        Ok(index) => previous[index].1
        Err(_) => Still(0.0)
      }
      let (visible_opacity, active) = match sample {
        Still(opacity) => (opacity, None)
        Animating(opacity, active) => (opacity, Some(active))
      }
      let fade = calculate_fade(
        visible_opacity,
        overlay_opacity,
        active,
        timeline_time_ms,
        animate~,
      )
      match fade {
        SetOpacity(0.0) => ranges
        _ => {
          ranges.push(({ start, end, }, fade))
          ranges
        }
      }
    },
  )
  ranges[:]
}
