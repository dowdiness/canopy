// Comprehensive test to find AST display bug
import { chromium } from 'playwright';

async function testInput(page, input, description) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`TEST: ${description}`);
  console.log(`${'='.repeat(60)}`);

  // Clear editor
  await page.locator('#editor').evaluate(el => el.textContent = '');
  await page.waitForTimeout(200);

  // Type the input
  console.log(`Typing: "${input}"`);
  await page.locator('#editor').click();

  // Type character by character to simulate real user input
  for (const char of input) {
    await page.keyboard.type(char);
    await page.waitForTimeout(50);
  }

  await page.waitForTimeout(500);

  // Get results
  const editorContent = await page.locator('#editor').evaluate(el => el.textContent);
  const astOutput = await page.locator('#ast-output').textContent();
  const errors = await page.locator('#error-output').textContent();

  console.log('Editor content:', JSON.stringify(editorContent));
  console.log('AST Output:');
  console.log(astOutput);
  console.log('Errors:', errors);

  return { editorContent, astOutput, errors };
}

async function main() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Capture console logs
  const consoleLogs = [];
  page.on('console', msg => {
    const text = msg.text();
    consoleLogs.push(text);
    if (text.includes('Error') || text.includes('AST') || text.includes('text')) {
      console.log('PAGE:', text);
    }
  });

  await page.goto('http://localhost:5173/');
  await page.waitForSelector('#editor');
  await page.waitForTimeout(1000);

  // Test various inputs
  const tests = [
    { input: '1', description: 'Single integer' },
    { input: '123', description: 'Multi-digit integer' },
    { input: 'x', description: 'Single variable' },
    { input: 'foo', description: 'Multi-character variable' },
    { input: '1 + 2', description: 'Simple addition' },
    { input: 'x + 1', description: 'Variable plus integer' },
    { input: '(x) => x', description: 'Arrow lambda function' },
    { input: '((x) => x) 5', description: 'Function application' },
    { input: 'if x then 1 else 0', description: 'Conditional expression' },
  ];

  const results = [];
  for (const test of tests) {
    const result = await testInput(page, test.input, test.description);
    results.push({ ...test, ...result });
  }

  // Check for discrepancies
  console.log('\n\n' + '='.repeat(60));
  console.log('ANALYSIS: Checking for AST bugs');
  console.log('='.repeat(60));

  for (const result of results) {
    const inputMatches = result.editorContent === result.input;
    if (!inputMatches) {
      console.log(`⚠️  MISMATCH: "${result.description}"`);
      console.log(`   Expected: "${result.input}"`);
      console.log(`   Got:      "${result.editorContent}"`);
    }

    // Check if AST is empty when it shouldn't be
    if (result.editorContent && result.astOutput.includes('Waiting for input')) {
      console.log(`⚠️  AST NOT UPDATING: "${result.description}"`);
      console.log(`   Editor has: "${result.editorContent}"`);
      console.log(`   But AST shows: ${result.astOutput.substring(0, 50)}`);
    }
  }

  await page.screenshot({ path: '/tmp/ast-comprehensive-test.png', fullPage: true });
  console.log('\nScreenshot saved to /tmp/ast-comprehensive-test.png');

  console.log('\nKeeping browser open for 10 seconds...');
  await page.waitForTimeout(10000);

  await browser.close();
}

main().catch(console.error);
