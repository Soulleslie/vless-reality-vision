#!/usr/bin/python3
"""Test-only transport redirects: real plugin/Certbot, local provider and Pebble."""
import os
import sys
import CloudFlare
from certbot.main import main

original = CloudFlare.CloudFlare


class LocalCloudflare(original):
    def __init__(self, *args, **kwargs):
        kwargs["base_url"] = "http://127.0.0.1:8055/client/v4"
        super().__init__(*args, **kwargs)


CloudFlare.CloudFlare = LocalCloudflare
args, skip = [], False
for arg in sys.argv[1:]:
    if skip:
        skip = False
        continue
    if arg == "--server":
        skip = True
    elif arg == "--dns-cloudflare-propagation-seconds":
        args.extend((arg, "0")); skip = True
    else:
        args.append(arg)
args.extend(("--server", "https://pebble:14000/dir", "--no-random-sleep-on-renew"))
if args[0] == "renew" and "--dry-run" not in args:
    args.append("--force-renewal")  # Test CA only: exercise normal due renewal now.
os.environ["REQUESTS_CA_BUNDLE"] = "/pebble-ca.pem"
sys.exit(main(args))
