"""Publish content-addressed external qs2 assets to GitHub Releases via PyGithub.

Called from data-raw/sync.R (upload = TRUE) as:

    uv run python data-raw/gh_upload.py   # upload manifest arrives on stdin

Replaces the former `gh` CLI path: PyGithub hits the REST API directly, so there
are no Windows argv-quoting workarounds. Identity is decided upstream in R -- `tag`
is the release_tag (<group>-<hash>, since GitHub rejects a bare 40/64-hex tag) and
the content address is already in `name` -- so this script only *publishes*; it
never computes or reasons about content identity.

stdin manifest:
    {"slug": "owner/repo",
     "target_commitish": "main",
     "assets": [{"group_id","tag","path","name"}, ...]}

Per asset: ensure a release for `tag` exists (create with notes if missing), then
attach `name` if not already present (else skip). The ONLY thing written to
stdout is a single JSON object {"results": [{group_id, tag, name, action}, ...]}
where action is "created" | "uploaded" | "skipped"; every human-readable line
goes to stderr so it cannot corrupt that stdout contract.

Auth: GITHUB_TOKEN or GH_TOKEN in the environment (sync.R injects the upload PAT,
sourced from METHYLCIPHER_UPLOAD_PAT, into this child process only). No gh CLI dependency.
"""

from __future__ import annotations

import json
import os
import sys

from github import Auth, Github, GithubException


def log(*args: object) -> None:
    print(*args, file=sys.stderr, flush=True)


def notes_for(group_id: str) -> str:
    return (
        f"External clock data for `{group_id}` (methylCIPHER). "
    )


def get_release(repo, tag: str):
    """Release for `tag`, or None when the tag/release does not exist yet."""
    try:
        return repo.get_release(tag)
    except GithubException as exc:
        if exc.status == 404:
            return None
        raise


def die_github(context: str, exc: GithubException) -> int:
    """Print GitHub's real status + response body (never a truncated traceback)."""
    body = exc.data if isinstance(exc.data, (dict, list)) else str(exc.data)
    log(f"error: GitHub API {exc.status} while {context}")
    log("  response: " + json.dumps(body, indent=2, default=str))
    if exc.status in (401, 403):
        log(
            "  hint: the token cannot write releases on this repo. Use a PAT with "
            "Contents: read/write (fine-grained) or the classic `repo` scope, and make "
            "sure it has access to the target repository."
        )
    elif exc.status == 422:
        log(
            "  hint: 422 usually means an invalid target_commitish (branch/commit not on "
            "the remote) or a release/tag_name that already exists."
        )
    return 4


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        log("error: GITHUB_TOKEN (or GH_TOKEN) is not set")
        return 2

    try:
        req = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        log(f"error: could not parse upload manifest on stdin: {exc}")
        return 2

    slug = req["slug"]
    target = req.get("target_commitish") or None
    assets = req.get("assets", [])

    gh = Github(auth=Auth.Token(token))
    repo = gh.get_repo(slug)

    results = []
    for a in assets:
        gid = a["group_id"]
        tag = a["tag"]
        path = a["path"]
        name = a["name"]

        if not tag:
            log(f"error: asset {gid} has no tag (payload_hash)")
            return 3
        if not os.path.exists(path):
            log(f"error: staged asset missing: {path}")
            return 3

        try:
            rel = get_release(repo, tag)
            if rel is None:
                commitish = target if target else repo.default_branch
                log(f"creating release tag {tag} on {slug} @ {commitish}")
                rel = repo.create_git_release(
                    tag=tag,
                    name=f"{gid} Data",
                    message=notes_for(gid),
                    target_commitish=commitish,
                )
                rel.upload_asset(path, name=name)
                log(f"uploaded {name} -> {slug} @ tag {tag} (new release)")
                results.append({"group_id": gid, "tag": tag, "name": name, "action": "created"})
                continue

            existing = {asset.name for asset in rel.get_assets()}
            if name in existing:
                log(f"skip {name} (already on {slug} @ tag {tag})")
                results.append({"group_id": gid, "tag": tag, "name": name, "action": "skipped"})
                continue

            log(f"release tag {tag} exists; uploading missing asset {name}")
            rel.upload_asset(path, name=name)
            log(f"uploaded {name} -> {slug} @ tag {tag}")
            results.append({"group_id": gid, "tag": tag, "name": name, "action": "uploaded"})
        except GithubException as exc:
            return die_github(f"publishing {gid} asset {name} (tag {tag})", exc)

    json.dump({"results": results}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
