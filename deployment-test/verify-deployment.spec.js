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
      url: `ws://${testClusterIP}/app/doc/Shared-Africa-Urbanization.qvf`,
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
    expect(layout.qTitle).to.equal('Shared-Africa-Urbanization');
  });

  it('Verify that the app includes at least one of the correct objects', async () => {
    const app = await qix.getActiveDoc();
    const obj = await app.getObject('PPPZWVQ');
    const objLayout = await obj.getLayout();
    expect(objLayout.title).to.equal('Average life expectancy (years)');
  });
});
