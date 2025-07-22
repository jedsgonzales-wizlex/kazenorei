// `prettier.config.js` or `.prettierrc.js`
import prettierConfigStandard from 'prettier-config-standard'
import merge from 'lodash.merge'

const modifiedConfig = merge({}, prettierConfigStandard, {
  // ... other modified settings here
})

export default modifiedConfig
