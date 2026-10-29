"""Creates the test certificates for https:// in http_simulator.py, in
credentials/tls/:

* ca.pem                     - test CA, paste into "CA CERTIFICATE" in the app
* server.pem, server.key     - certificate of the simulator, signed by the CA

The server certificate is valid for localhost and the IP addresses given as
arguments (default: SIMULATOR_HOST or 172.30.13.2, plus 127.0.0.1 and the
Android emulator's 10.0.2.2), since the app checks the address against it.

    python make_test_certs.py [IP ...]

Only for tests: the private key is not protected.
"""

import datetime
import ipaddress
import os
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

OUT_DIR = Path(__file__).resolve().parent / "credentials" / "tls"
VALID_DAYS = 825


def _name(common_name):
    return x509.Name(
        [
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Device simulator"),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ]
    )


def _certificate(subject, key, issuer, issuer_key, extensions):
    now = datetime.datetime.now(datetime.timezone.utc)
    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=VALID_DAYS))
    )
    for extension, critical in extensions:
        builder = builder.add_extension(extension, critical=critical)
    return builder.sign(issuer_key, hashes.SHA256())


def _write(name, data):
    (OUT_DIR / name).write_bytes(data)
    print("wrote", OUT_DIR / name)


def _pem(certificate):
    return certificate.public_bytes(serialization.Encoding.PEM)


def _key_pem(key):
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )


def main(addresses):
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = _name("Simulator Test CA")
    ca = _certificate(
        ca_name,
        ca_key,
        ca_name,
        ca_key,
        [
            (x509.BasicConstraints(ca=True, path_length=0), True),
            (
                x509.KeyUsage(
                    digital_signature=True, key_cert_sign=True, crl_sign=True,
                    content_commitment=False, key_encipherment=False,
                    data_encipherment=False, key_agreement=False,
                    encipher_only=False, decipher_only=False,
                ),
                True,
            ),
        ],
    )

    server_key = ec.generate_private_key(ec.SECP256R1())
    server = _certificate(
        _name("simulator"),
        server_key,
        ca_name,
        ca_key,
        [
            (x509.BasicConstraints(ca=False, path_length=None), True),
            (x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), False),
            (
                x509.SubjectAlternativeName(
                    [x509.DNSName("localhost")]
                    + [x509.IPAddress(ipaddress.ip_address(a)) for a in addresses]
                ),
                False,
            ),
        ],
    )

    _write("ca.pem", _pem(ca))
    _write("server.pem", _pem(server))
    _write("server.key", _key_pem(server_key))


if __name__ == "__main__":
    host = os.environ.get("SIMULATOR_HOST", "172.30.13.2")
    main(sys.argv[1:] or [host, "127.0.0.1", "10.0.2.2"])
