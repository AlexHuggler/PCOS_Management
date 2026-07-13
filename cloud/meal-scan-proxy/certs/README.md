# Bundled Apple trust roots

These DER certificates are published by Apple and are bundled so production StoreKit verification does not depend on an unpinned environment variable. The `.cer` bytes are base64-encoded for source control; startup decodes and parses every file with Node's `X509Certificate` before constructing Apple's `SignedDataVerifier`.

Fetched from Apple's Certificate Authority site on 2026-07-13:

| File | Official source | SHA-256 of decoded DER |
| --- | --- | --- |
| `AppleIncRootCertificate.cer.base64` | <https://www.apple.com/appleca/AppleIncRootCertificate.cer> | `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024` |
| `AppleRootCA-G2.cer.base64` | <https://www.apple.com/certificateauthority/AppleRootCA-G2.cer> | `c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050` |
| `AppleRootCA-G3.cer.base64` | <https://www.apple.com/certificateauthority/AppleRootCA-G3.cer> | `63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179` |

When Apple changes its published trust-root guidance, update these files and hashes together and rerun the verifier tests before deployment.
