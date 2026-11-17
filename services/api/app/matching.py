"""Matching a submitted title to TMDB, and suggesting a VJ credit.

Pure functions, with no database or network, so the rules in
docs/step-09a-vj-catalogue-plan.md, sections 2 and 4, can be tested on their
own. The admin routes feed them what TMDB and the database hold.
"""

import re
import unicodedata
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from uuid import UUID

from app.tmdb import SearchResult

# Words that describe a VJ file rather than the film, removed before searching.
_FILLER = re.compile(
    r"\b(?:luganda|translated|translation|full\s+movie|official|"
    r"\d{3,4}p|hd|fhd|uhd|4k|hdrip|webrip|web\s*dl|bluray|brrip|dvdrip|"
    r"x26[45]|hevc|h26[45]|aac|mp4|mkv|avi)\b",
    re.IGNORECASE,
)
# A year in brackets, or at the end: "Fast X (2023)", "Fast.X.2023".
_YEAR = re.compile(r"[(\[]?\b(19\d\d|20\d\d)\b[)\]]?")
# "VJ" and the one word after it, for VJs not yet known.
_VJ_WORD = re.compile(r"\bvj[\s._-]*[a-z0-9]+", re.IGNORECASE)
_SEPARATORS = re.compile(r"[._\-\[\]()]+")


def _spaces(text: str) -> str:
    return " ".join(text.split())


def clean_title(title: str, vj_names: Iterable[str] = ()) -> tuple[str, int | None]:
    """The title to search TMDB with, and a year found in it, if any.

    Removes known VJ names, "VJ" with the word after it, words such as
    "Luganda" and quality tags. Keeps the original if cleaning would leave
    nothing."""
    text = _SEPARATORS.sub(" ", title)
    for name in sorted(set(vj_names), key=len, reverse=True):
        if name.strip():
            text = re.sub(
                r"\b" + r"\s+".join(map(re.escape, name.split())) + r"\b",
                " ",
                text,
                flags=re.IGNORECASE,
            )
    text = _VJ_WORD.sub(" ", text)
    text = _FILLER.sub(" ", text)
    years = _YEAR.findall(text)
    text = _YEAR.sub(" ", text)
    cleaned = _spaces(text)
    if not cleaned:
        # Nothing left, as for "1917": the title is what was submitted.
        return _spaces(title), None
    return cleaned, (int(years[-1]) if years else None)


def normalize(title: str) -> str:
    """For comparing titles: no accents, case, punctuation or leading "The"."""
    text = unicodedata.normalize("NFKD", title)
    text = "".join(ch for ch in text if not unicodedata.combining(ch)).lower()
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    return re.sub(r"^the ", "", text)


def clear_match(
    results: Sequence[SearchResult], title: str, year: int | None
) -> SearchResult | None:
    """The one result whose title or original title is the cleaned title,
    and from the year if one was given. None if there isn't exactly one."""
    wanted = normalize(title)
    if not wanted:
        return None
    same = [
        r
        for r in results
        if normalize(r.title) == wanted
        or (r.original_title and normalize(r.original_title) == wanted)
    ]
    if year is not None:
        same = [r for r in same if r.year == year]
    return same[0] if len(same) == 1 else None


# --- VJ credit ---------------------------------------------------------------


@dataclass(frozen=True)
class KnownVj:
    id: UUID
    name: str
    match_names: tuple[str, ...] = ()


@dataclass(frozen=True)
class Suggestion:
    """A VJ the file seems to name. vj_id is None for a name no VJ has yet,
    which the admin can add."""

    vj_id: UUID | None
    name: str
    found_in: str


# "VJ" and one or two words after it. The second is never another "VJ".
_VJ_PHRASE = re.compile(
    r"\bvj[\s._-]*([a-z0-9]+)(?:[\s._-]+(?!vj\b)([a-z0-9]+))?", re.IGNORECASE
)
MAX_SUGGESTIONS = 5


def _compact(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", normalize(text))


def _keys(vj: KnownVj) -> set[str]:
    keys = set()
    for name in (vj.name, *vj.match_names):
        compact = _compact(name)
        if compact:
            keys.add(compact)
            keys.add(compact.removeprefix("vj"))
            keys.add("vj" + compact.removeprefix("vj"))
    return keys - {"", "vj"}


def suggest_credit(
    sources: Iterable[tuple[str, str | None]], vjs: Sequence[KnownVj]
) -> list[Suggestion]:
    """VJs named in each (where, text) pair, such as ("file name",
    "Fast.X.VJ.Ice.P.mp4"). Known VJs first, in the order found; then
    names no VJ has yet."""
    sources = list(sources)
    by_key = {key: vj for vj in vjs for key in _keys(vj)}
    known: list[Suggestion] = []
    unknown: list[Suggestion] = []
    for where, text in sources:
        if not text:
            continue
        for first, second in _VJ_PHRASE.findall(text):
            words = [first] + ([second] if second else [])
            match = None
            # The longer reading first: "VJ Ice P" before "VJ Ice".
            for count in range(len(words), 0, -1):
                match = by_key.get("vj" + _compact("".join(words[:count])))
                if match:
                    break
            if match:
                if all(s.vj_id != match.id for s in known):
                    known.append(Suggestion(match.id, match.name, where))
                continue
            name = f"VJ {first.capitalize()}"
            if all(s.name.lower() != name.lower() for s in unknown):
                unknown.append(Suggestion(None, name, where))
    # Known VJs named without "VJ", such as another spelling in the tags, as
    # whole words of at least 4 letters, so "Emmy" isn't found in "Emmys".
    for where, text in sources:
        words = f" {normalize(_SEPARATORS.sub(' ', text or ''))} "
        for vj in vjs:
            if any(s.vj_id == vj.id for s in known):
                continue
            for name in (vj.name, *vj.match_names):
                phrase = normalize(name)
                bare = phrase.removeprefix("vj ")
                if any(
                    len(p.replace(" ", "")) >= 4 and f" {p} " in words
                    for p in {phrase, bare}
                ):
                    known.append(Suggestion(vj.id, vj.name, where))
                    break
    return (known + unknown)[:MAX_SUGGESTIONS]
