from __future__ import annotations

from typing import Any

from addko_bridge import emit

CRYPTO_SESSION_SYSTEM_NONE = 0
CRYPTO_SESSION_SYSTEM_WIDEVINE = 1
CRYPTO_SESSION_SYSTEM_PLAYREADY = 2


class CryptoSession:
    def __init__(self, keySystem: str, cipherAlgorithm: str = "", macAlgorithm: str = "") -> None:
        self.keySystem = keySystem
        self.cipherAlgorithm = cipherAlgorithm
        self.macAlgorithm = macAlgorithm
        emit(
            "xbmcdrm.CryptoSession.create",
            key_system=keySystem,
            cipher_algorithm=cipherAlgorithm,
            mac_algorithm=macAlgorithm,
        )

    def GetKeyRequest(self, init: bytes, mimeType: str, offlineKey: bool = False, optionalParameters: dict[str, str] | None = None) -> bytes:
        emit(
            "xbmcdrm.CryptoSession.GetKeyRequest",
            mime_type=mimeType,
            offline_key=offlineKey,
        )
        return b""

    def ProvideKeyResponse(self, response: bytes) -> str:
        emit("xbmcdrm.CryptoSession.ProvideKeyResponse", response_size=len(response))
        return ""

    def RemoveKeys(self) -> None:
        emit("xbmcdrm.CryptoSession.RemoveKeys")

    def Decrypt(self, cipherKeyId: bytes, input: bytes, iv: bytes) -> bytes:
        emit("xbmcdrm.CryptoSession.Decrypt", input_size=len(input))
        return input

    def Sign(self, message: bytes, keyId: bytes) -> bytes:
        emit("xbmcdrm.CryptoSession.Sign", message_size=len(message))
        return b""

    def Verify(self, message: bytes, signature: bytes, keyId: bytes) -> bool:
        emit("xbmcdrm.CryptoSession.Verify", message_size=len(message))
        return False
