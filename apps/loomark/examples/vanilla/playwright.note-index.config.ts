import standalone from "./playwright.standalone.config"

export default { ...standalone, testMatch: "note-index.spec.ts" }
