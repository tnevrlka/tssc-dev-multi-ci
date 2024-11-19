/*
 * Render a Nunjucks template
 *
 * Usage:
 *   $ node render.cjs <templateFile> <dataFile> [<key1>=<val1>] [<key2>=<val2>] ...
 *
 */

const fs = require('fs')
const yaml = require('js-yaml')
const nunjucks = require('nunjucks')

function readFile(fileName) {
  return fs.readFileSync(fileName, 'utf-8')
}

function parseDataFile(fileName) {
  const fileContent = readFile(fileName)
  if (fileName.endsWith('.yaml') || fileName.endsWith('.yml')) {
    return yaml.load(fileContent)
  }
  return JSON.parse(fileContent)
}

function nunjucksRender(templateFile, contextFile, extraData) {
  const contextData = { ...parseDataFile(contextFile), ...extraData }
  return nunjucks.renderString(readFile(templateFile), contextData)
}

// Set path to find partials
const env = nunjucks.configure('templates/partials', {
  autoescape: false,
})

// Custom filters
const filters = {
  // For putting literal {{ }} chars in the output
  'inCurlies': (str) => `\{{ ${str} }}`,
  'concat': (arr1, arr2) => arr1.concat(arr2),
  // Note: this is an indirect eval, so the code can only access globals
  // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/eval#direct_and_indirect_eval
  'eval': (code) => eval?.(code),
  'eval_if_condition': (obj) => !obj.if || eval?.(obj.if),
}

function setupFilters(env, filters) {
  for (const f in filters) {
    env.addFilter(f, filters[f])
  }
}

// Custom globals
function setupGlobals(env, contextFile, extraData) {
  const contextData = { ...parseDataFile(contextFile), ...extraData }

  const globals = {
    // Useful sometimes to get just the right amount of line breaks
    'nl': "\n",
    'nlnl': "\n\n",
  }

  // Expect this to be the name of the file being generated
  const targetFile = contextData.targetFile

  const fileNameMatchers = {
    'Jenkins': /Jenkins|groovy/,
    'GitHub': /github/,
    'GitLab': /gitlab/,
    'Azure': /azure/,
    'Bash': /\.sh$/,
  }

  for (const m in fileNameMatchers) {
    globals[`is${m}`] = fileNameMatchers[m].test(targetFile)
  }

  for (const g in globals) {
    env.addGlobal(g, globals[g])
    globalThis[g] = globals[g]
  }
}

// Read and verify required params
const [templateFile, contextFile] = process.argv.slice(2)
if (!templateFile || !contextFile) {
  console.error("Usage:\n  node render.cjs <templateFile> <dataFile> [<key1>=<val1>] [<key2>=<val2>] ...")
  process.exit(1)
}

// Read optional key=value params
const paramData = {}
const keyValArgs = process.argv.slice(4)
for (const i in keyValArgs) {
  const [key, val] = keyValArgs[i].split('=')
  paramData[key] = val
}

// Setup custom stuff
setupFilters(env, filters)
setupGlobals(env, contextFile, paramData)

// Render output
output = nunjucksRender(templateFile, contextFile, paramData)
console.log(output.trimEnd())
