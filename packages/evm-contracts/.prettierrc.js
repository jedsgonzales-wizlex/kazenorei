// `prettier.config.js` or `.prettierrc.js`
import prettierConfigSolidity from 'prettier-config-solidity';
import merge from 'lodash.merge';

const modifiedConfig = merge(
  {},
  prettierConfigSolidity,
  {
    // ... other modified settings here
  }
)

export default modifiedConfig;
