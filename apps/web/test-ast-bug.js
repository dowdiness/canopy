// Test script to investigate AST display bug
import { chromium } from 'playwright';

async function main() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Listen to console messages from the page
  page.on('console', msg => {
    console.log('PAGE LOG:', msg.text());
  });

  // Navigate to the app
  console.log('Navigating to http://localhost:5173/');
  await page.goto('http://localhost:5173/');

  // Wait for the editor to be ready
  await page.waitForSelector('#editor');
  console.log('Editor element found');

  // Wait for the app to initialize
  await page.waitForTimeout(1000);

  // Get initial state
  const initialAST = await page.locator('#ast-output').textContent();
  console.log('Initial AST:', initialAST);

  // Type some text in the editor
  const testInput = 'x';
  console.log(`\nTyping: "${testInput}"`);
  await page.locator('#editor').click();
  await page.locator('#editor').type(testInput);

  // Wait for the UI to update
  await page.waitForTimeout(500);

  // Get the editor content
  const editorTextContent = await page.locator('#editor').evaluate(el => el.textContent);
  const editorInnerHTML = await page.locator('#editor').evaluate(el => el.innerHTML);
  const editorInnerText = await page.locator('#editor').evaluate(el => el.innerText);

  console.log('\n=== Editor Content After Typing ===');
  console.log('textContent:', JSON.stringify(editorTextContent));
  console.log('innerHTML:', editorInnerHTML);
  console.log('innerText:', JSON.stringify(editorInnerText));

  // Get the AST output
  const astOutput = await page.locator('#ast-output').textContent();
  console.log('\n=== AST Output ===');
  console.log(astOutput);

  // Get any errors
  const errors = await page.locator('#error-output').textContent();
  console.log('\n=== Errors ===');
  console.log(errors);

  // Take a screenshot
  await page.screenshot({ path: '/tmp/ast-bug-screenshot.png', fullPage: true });
  console.log('\nScreenshot saved to /tmp/ast-bug-screenshot.png');

  // Try typing more characters
  console.log('\nTyping additional character: "y"');
  await page.locator('#editor').type('y');
  await page.waitForTimeout(500);

  const editorTextContent2 = await page.locator('#editor').evaluate(el => el.textContent);
  const astOutput2 = await page.locator('#ast-output').textContent();

  console.log('\n=== After typing "y" ===');
  console.log('Editor textContent:', JSON.stringify(editorTextContent2));
  console.log('AST Output:');
  console.log(astOutput2);

  // Keep browser open for manual inspection
  console.log('\nBrowser will stay open for 30 seconds for manual inspection...');
  await page.waitForTimeout(30000);

  await browser.close();
}

main().catch(console.error);
