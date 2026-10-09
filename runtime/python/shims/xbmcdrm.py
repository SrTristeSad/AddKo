from __future__ import annotations

"""Kodi Omega ``xbmcdrm`` compatibility surface.

The public method names and argument order mirror Kodi 21's
``DrmCryptoSession.h``. AddKo currently exposes the API contract and forwards
session activity to the host; native MediaDrm-backed cryptographic operations
are still a separate runtime milestone.
"""

from typing import Any

from addko_bridge import emit

CRYPTO_SESSION_SYSTEM_NONE = 0
CRYPTO_SESSION_SYSTEM_WIDEVINE = 1
CRYPTO_SESSION_SYSTEM_PLAYREADY = 2


class CryptoSession:
    def __init__(
        self,
        UUID: str,
        cipherAlgorithm: str = "",
        macAlgorithm: str = "",
    ) -> None:
        self.UUID = str(UUID)
        # keySystem was used by an early AddKo shim. Keep it as an alias so
        # addons that introspected the object during development do not break.
        self.keySystem = self.UUID
        self.cipherAlgorithm = str(cipherAlgorithm)
        self.macAlgorithm = str(macAlgorithm)
        self._properties: dict[str, str] = {}
        emit(
            "xbmcdrm.CryptoSession.create",
            uuid=self.UUID,
            cipher_algorithm=self.cipherAlgorithm,
            mac_algorithm=self.macAlgorithm,
        )

    def GetKeyRequest(
        self,
        init: bytes | bytearray,
        mimeType: str,
        offlineKey: bool,
        optionalParameters: dict[str, str] | None = None,
    ) -> bytes:
        emit(
            "xbmcdrm.CryptoSession.GetKeyRequest",
            init_size=len(init),
            mime_type=str(mimeType),
            offline_key=bool(offlineKey),
            optional_parameters=dict(optionalParameters or {}),
        )
        # The direct CryptoSession API needs Android MediaDrm/native Kodi DRM to
        # produce a real challenge. Returning an empty buffer preserves Kodi's
        # bytes-shaped contract without inventing key material.
        return b""

    def GetPropertyString(self, name: str) -> str:
        key = str(name)
        emit("xbmcdrm.CryptoSession.GetPropertyString", name=key)
        return self._properties.get(key, "")

    def ProvideKeyResponse(self, response: bytes | bytearray) -> str:
        emit(
            "xbmcdrm.CryptoSession.ProvideKeyResponse",
            response_size=len(response),
        )
        return ""

    def RemoveKeys(self) -> None:
        emit("xbmcdrm.CryptoSession.RemoveKeys")

    def RestoreKeys(self, keySetId: str) -> None:
        emit("xbmcdrm.CryptoSession.RestoreKeys", key_set_id=str(keySetId))

    def SetPropertyString(self, name: str, value: str) -> None:
        key = str(name)
        self._properties[key] = str(value)
        emit(
            "xbmcdrm.CryptoSession.SetPropertyString",
            name=key,
            value=str(value),
        )

    def Decrypt(
        self,
        cipherKeyId: bytes | bytearray,
        input: bytes | bytearray,
        iv: bytes | bytearray,
    ) -> bytes:
        emit(
            "xbmcdrm.CryptoSession.Decrypt",
            key_id_size=len(cipherKeyId),
            input_size=len(input),
            iv_size=len(iv),
        )
        # Do not fabricate decrypted content. Until MediaDrm is connected, the
        # only safe bytes-shaped fallback is an empty result.
        return b""

    def Encrypt(
        self,
        cipherKeyId: bytes | bytearray,
        input: bytes | bytearray,
        iv: bytes | bytearray,
    ) -> bytes:
        emit(
            "xbmcdrm.CryptoSession.Encrypt",
            key_id_size=len(cipherKeyId),
            input_size=len(input),
            iv_size=len(iv),
        )
        return b""

    def Sign(
        self,
        macKeyId: bytes | bytearray,
        message: bytes | bytearray,
    ) -> bytes:
        emit(
            "xbmcdrm.CryptoSession.Sign",
            key_id_size=len(macKeyId),
            message_size=len(message),
        )
        return b""

    def Verify(
        self,
        macKeyId: bytes | bytearray,
        message: bytes | bytearray,
        signature: bytes | bytearray,
    ) -> bool:
        emit(
            "xbmcdrm.CryptoSession.Verify",
            key_id_size=len(macKeyId),
            message_size=len(message),
            signature_size=len(signature),
        )
        return False


__all__ = [
    "CRYPTO_SESSION_SYSTEM_NONE",
    "CRYPTO_SESSION_SYSTEM_WIDEVINE",
    "CRYPTO_SESSION_SYSTEM_PLAYREADY",
    "CryptoSession",
]
