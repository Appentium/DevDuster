#!/usr/bin/env python3
import email.utils
import re
import sys

appcast, version, build, size, signature, url = sys.argv[1:7]
item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>https://devduster.com/changelog.html</sparkle:fullReleaseNotesLink>
            <enclosure url="{url}" length="{size}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
        </item>
"""
text = open(appcast).read()
if f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in text:
    sys.exit(f"{appcast} already lists {version}")
text = re.sub(r"(<language>[^<]*</language>\n)", lambda m: m.group(1) + item, text, count=1)
open(appcast, "w").write(text)
