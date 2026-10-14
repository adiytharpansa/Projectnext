/**
 * SHIM WAJIB PERTAMA — diimpor paling awal di index.ts, sebelum axios/cheerio.
 *
 * axios fetch-adapter meng-capture global Request saat modulnya dimuat, dan
 * workerd menolak field RequestInit `cache`/`mode`/dll. Patch di sini
 * memastikan axios membundel konstruktor yang sudah dibersihkan.
 * Modul ini TIDAK BOLEH mengimpor apa pun dari ../../src (agar evaluasi
 * axios terjadi setelah patch terpasang).
 */

const DROP_INIT = new Set(['cache', 'credentials', 'mode', 'referrerPolicy']);

function stripInit(init?: RequestInit): RequestInit | undefined {
  if (!init) return init;
  const clean: Record<string, unknown> = { ...(init as Record<string, unknown>) };
  for (const k of DROP_INIT) delete clean[k];
  return clean as RequestInit;
}

const nativeFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = ((input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) =>
  nativeFetch(input, stripInit(init))) as typeof fetch;

const NativeRequest = globalThis.Request;
function PatchedRequest(
  input: ConstructorParameters<typeof Request>[0],
  init?: RequestInit,
): Request {
  return new NativeRequest(input, stripInit(init));
}
PatchedRequest.prototype = NativeRequest.prototype;
Object.setPrototypeOf(PatchedRequest, NativeRequest);
globalThis.Request = PatchedRequest as unknown as typeof Request;

export {};
