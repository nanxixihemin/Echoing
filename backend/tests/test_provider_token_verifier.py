from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from services.provider_token_verifier import ProviderTokenVerifier, ProviderVerificationError


class StaticJwksClient:
    def __init__(self, key: rsa.RSAPublicKey) -> None:
        self.key = key

    def get_signing_key_from_jwt(self, token: str) -> SimpleNamespace:
        return SimpleNamespace(key=self.key)


class ProviderTokenVerifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.public_key = cls.private_key.public_key()

    def test_agc_verifies_signature_issuer_audience_and_expiry(self) -> None:
        os.environ["AGC_PROJECT_ID"] = "project-123"
        verifier = ProviderTokenVerifier()
        verifier._agc_keys = {
            "kid-1": self.public_key.public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            ).decode("ascii")
        }
        verifier._agc_keys_loaded_at = time.monotonic()
        now = int(time.time())
        token = jwt.encode(
            {
                "sub": "agc-user",
                "aud": "project-123",
                "iss": "https://agc.developer.huawei.com/project-123",
                "iat": now,
                "exp": now + 300,
                "email": "USER@example.com",
                "email_verified": True,
            },
            self.private_key,
            algorithm="PS256",
            headers={"kid": "kid-1", "typ": "JWT"},
        )
        identity = verifier.verify_agc(token)
        self.assertEqual("agc-user", identity.provider_user_id)
        self.assertEqual("user@example.com", identity.email)
        self.assertTrue(identity.email_verified)

        forged = jwt.encode(
            {
                "sub": "agc-user",
                "aud": "wrong-project",
                "iss": "https://agc.developer.huawei.com/project-123",
                "iat": now,
                "exp": now + 300,
            },
            self.private_key,
            algorithm="PS256",
            headers={"kid": "kid-1"},
        )
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_agc(forged)

    def test_huawei_verifies_nonce_and_authorized_party(self) -> None:
        os.environ["HUAWEI_ACCOUNT_CLIENT_ID"] = "client-123"
        verifier = ProviderTokenVerifier()
        verifier._huawei_discovery = {
            "issuer": "https://accounts.huawei.com",
            "jwks_uri": "https://oauth-login.cloud.huawei.com/oauth2/v3/certs",
            "id_token_signing_alg_values_supported": ["RS256", "PS256"],
        }
        verifier._huawei_jwks_client = StaticJwksClient(self.public_key)
        now = int(time.time())
        token = jwt.encode(
            {
                "sub": "huawei-user",
                "aud": "client-123",
                "azp": "client-123",
                "iss": "https://accounts.huawei.com",
                "iat": now,
                "exp": now + 300,
                "nonce": "nonce-123",
            },
            self.private_key,
            algorithm="PS256",
            headers={"kid": "kid-1"},
        )
        identity = verifier.verify_huawei(token, "nonce-123")
        self.assertEqual("huawei-user", identity.provider_user_id)
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei(token, "forged-nonce")


if __name__ == "__main__":
    unittest.main()
