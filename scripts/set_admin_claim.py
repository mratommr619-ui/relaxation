import argparse
import os

import firebase_admin
from firebase_admin import auth, credentials


def main() -> None:
    parser = argparse.ArgumentParser(description="Grant Relaxation Studio admin claim.")
    parser.add_argument("--service-account", required=True)
    parser.add_argument("--email", required=True)
    args = parser.parse_args()

    cred_path = os.path.abspath(args.service_account)
    firebase_admin.initialize_app(credentials.Certificate(cred_path))
    user = auth.get_user_by_email(args.email)
    claims = user.custom_claims or {}
    claims["admin"] = True
    auth.set_custom_user_claims(user.uid, claims)
    print(f"Granted admin claim to {args.email}")


if __name__ == "__main__":
    main()
