import { LRLanguage, LanguageSupport } from "@codemirror/language";
import { styleTags, tags as t } from "@lezer/highlight";
import { parser } from "./lambda-parser.js";

const lambdaHighlight = styleTags({
  "fn let if then else": t.keyword,
  "FnDef/VariableName LetDef/VariableName": t.definition(t.variableName),
  VariableName: t.variableName,
  Number: t.number,
  Operator: t.arithmeticOperator,
  "( ) { }": t.paren,
  ", : ;": t.punctuation,
  "= => ->": t.definitionOperator,
});

const lambdaLanguage = LRLanguage.define({
  name: "lambda",
  parser: parser.configure({ props: [lambdaHighlight] }),
  languageData: {
    commentTokens: {},
  },
});

export function lambda(): LanguageSupport {
  return new LanguageSupport(lambdaLanguage);
}
