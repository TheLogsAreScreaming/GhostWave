import { test } from 'node:test';
import assert from 'node:assert/strict';
import { installerFor } from '../installer.js';
test('nRF and ESP routes use distinct installation packages', () => {
  const version = { version: '0.1.0-dev.8+build.abcdef' };
  assert.equal(installerFor({ id: 'rak4631' }, version).extension, 'uf2');
  assert.equal(installerFor({ id: 'heltec_v3', transport: 'esp-web-tools' }, version).download, 'firmware/heltec_v3/0.1.0-dev.8+build.abcdef/installer.zip');
});
test('missing releases and catalog-only entries cannot flash', () => {
  assert.equal(installerFor({ id: 'heltec_v3' }, null), null);
  assert.equal(installerFor({ id: 'heltec_v3', catalogOnly: true }, {version:'1'}), null);
});
test('unknown transports and path traversal are refused', () => {
  assert.throws(() => installerFor({ id: 'x', transport: 'guess' }, {version:'1'}));
  assert.throws(() => installerFor({ id: '../x' }, {version:'1'}));
  assert.throws(() => installerFor({ id: 'x' }, {version:'1/../../x'}));
});
