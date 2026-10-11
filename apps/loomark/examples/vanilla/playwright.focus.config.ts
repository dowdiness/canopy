import standalone from "./playwright.standalone.config"

export default { ...standalone, testMatch: "writing-focus.spec.ts" }
