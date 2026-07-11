// Inline range slider widget for integer literal nodes.
//
// Renders an <input type="range"> next to the CM6 inline editor
// so users can scrub numeric values with direct manipulation.

import { WidgetType } from "@codemirror/view";

/**
 * CM6 WidgetType that renders an inline range slider.
 * Used by TermLeafView to augment int_literal nodes.
 */
export class SliderWidget extends WidgetType {
  constructor(
    private value: number,
    private onChange: (newValue: number) => void,
  ) {
    super();
  }

  toDOM(): HTMLElement {
    const wrapper = document.createElement("span");
    wrapper.className = "canopy-slider";

    const input = document.createElement("input");
    input.type = "range";
    input.min = "0";
    input.max = "100";
    input.value = String(this.value);
    input.style.width = "60px";
    input.style.height = "4px";
    input.style.verticalAlign = "middle";
    input.style.marginLeft = "4px";

    input.addEventListener("input", (e) => {
      const newVal = Number((e.target as HTMLInputElement).value);
      this.onChange(newVal);
    });

    wrapper.appendChild(input);
    return wrapper;
  }

  eq(other: SliderWidget): boolean {
    return this.value === other.value;
  }

  ignoreEvent(): boolean {
    return false; // Allow slider interaction
  }
}
