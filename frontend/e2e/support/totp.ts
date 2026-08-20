import { Buffer } from "node:buffer";
import { createHmac } from "node:crypto";

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const periodMs = 30_000;

const decodeBase32 = (raw: string): Buffer => {
  const normalized = raw.replace(/[\s=-]/g, "").toUpperCase();
  let buffer = 0;
  let bits = 0;
  const bytes: number[] = [];
  for (const character of normalized) {
    const digit = alphabet.indexOf(character);
    if (digit < 0) throw new Error("Secret TOTP sintetico invalido");
    buffer = (buffer << 5) | digit;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >>> bits) & 0xff);
    }
  }
  if (bytes.length < 20) throw new Error("Secret TOTP sintetico demasiado corto");
  return Buffer.from(bytes);
};

const codeAt = (secret: Buffer, counter: number): string => {
  const value = Buffer.alloc(8);
  value.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", secret).update(value).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  return String(binary % 1_000_000).padStart(6, "0");
};

export class TotpSequence {
  private readonly secret: Buffer;
  private lastCounter: number;

  constructor(rawSecret: string, bootstrapCounter: number) {
    this.secret = decodeBase32(rawSecret);
    this.lastCounter = bootstrapCounter;
  }

  async next(): Promise<string> {
    const targetCounter = Math.max(
      Math.floor(Date.now() / periodMs),
      this.lastCounter + 1,
    );
    const waitMs = targetCounter * periodMs - Date.now() + 250;
    if (waitMs > 0) {
      await new Promise<void>((resolve) => setTimeout(resolve, waitMs));
    }
    const current = Math.floor(Date.now() / periodMs);
    if (current <= this.lastCounter) {
      throw new Error("El reloj no avanzo a un contador TOTP nuevo");
    }
    this.lastCounter = current;
    return codeAt(this.secret, current);
  }
}
