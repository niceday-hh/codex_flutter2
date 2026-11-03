import {QuantizerCelebi} from './node_modules/@material/material-color-utilities/quantize/quantizer_celebi.js';
import {Score} from './node_modules/@material/material-color-utilities/score/score.js';
import {hexFromArgb} from './node_modules/@material/material-color-utilities/utils/string_utils.js';
import {Scheme} from './node_modules/@material/material-color-utilities/scheme/scheme.js';
let input = ''; for await (const chunk of process.stdin) input += chunk;
const images = JSON.parse(input), output = {};
for (const [asset, pixels] of Object.entries(images)) {
  const seed = Score.score(QuantizerCelebi.quantize(pixels, 128))[0];
  const roles = scheme => Object.fromEntries(Object.entries(scheme.toJSON()).map(([key, value]) => [key, hexFromArgb(value)]));
  output[asset] = {seed: hexFromArgb(seed), light: roles(Scheme.light(seed)), dark: roles(Scheme.dark(seed))};
}
process.stdout.write(JSON.stringify(output));
