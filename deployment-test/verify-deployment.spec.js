const enigma = require('enigma.js');
const WebSocket = require('ws');
const schema = require('enigma.js/schemas/12.20.0.json');

describe('Verify the Deployment', () => {
  let qix;
  let session;
  const testClusterIP = process.env.TEST_CLUSTER_IP;

  beforeEach(async () => {
    session = enigma.create({
      schema,
      url: `ws://${testClusterIP}/app/doc/5f5f03fe-00f3-4a4b-ac52-db32152a7e44`,
      createSocket: url => new WebSocket(url),
    });
    qix = await session.open();
  });

  afterEach(async () => {
    await session.close();
  });

  it('Verify that the correct app is opened', async () => {
    const app = await qix.getActiveDoc();
    const layout = await app.getAppLayout();
    expect(layout.qTitle).to.equal('5f5f03fe-00f3-4a4b-ac52-db32152a7e44');
  });

  it('Verify that the app includes at least one of the correct fields', async () => {
    const app = await qix.getActiveDoc();
    const landField = await app.getFieldDescription('Land Area');
    expect(landField.qName).to.equal('Land Area');
  });

  it('Verify that reload is not possible', async () => {
    const app = await qix.getActiveDoc();
    try {
      const result = await app.doReload();
      throw new Error("Reload success");
    } catch (err) {
      expect(err.message).to.equal('Access denied');
    }
  });
});
