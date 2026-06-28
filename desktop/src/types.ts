export type DeviceInfo = {
  identityId: bigint;
  pubKey: string;
  label: string;
  addedAt: bigint;
  revoked: boolean;
  exists: boolean;
};
