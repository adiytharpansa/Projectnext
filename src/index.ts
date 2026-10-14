import 'dotenv/config'; // WAJIB pertama: hoisting ESM menilai ./config sebelum dotenv.config()
import { createApp } from './app';
import { appConfig } from './config';

const app = createApp();

app.listen(appConfig.port, () => {
  console.log(`[projectnext] running on http://localhost:${appConfig.port} (${appConfig.nodeEnv})`);
  console.log(`[projectnext] gogo=${appConfig.gogoBaseUrl} samehadaku=${appConfig.samehadakuBaseUrl}`);
});
