"""Categories, Phase 4: admins tag titles; viewers browse and filter by them.

The database tests need a local test Postgres: see tests/db_support.py.
"""

# The owner, admin, api and tmdb fixtures come from test_admin; ruff reads
# each use of them as a parameter as redefining the import.
# ruff: noqa: F811

import uuid

import psycopg
import pytest

from app.admin_catalogue import AdminError, category_slug, normalise_category
from tests.db_support import needs_database
from tests.test_admin import admin, api, draft, owner, tmdb  # noqa: F401
from tests.test_database import as_user
from tests.test_discovery import title
from tests.test_viewer import vj

SEEDS = ["Indian", "Nollywood", "Korean", "Chinese", "Action Classics", "Kids"]


# --- Without a database --------------------------------------------------------


@pytest.mark.parametrize(
    ("typed", "saved"),
    [("  Indian ", "Indian"), ("Action \t  Classics", "Action Classics")],
)
def test_names_are_trimmed_with_single_spaces(typed, saved):
    assert normalise_category(typed) == saved


@pytest.mark.parametrize(
    ("typed", "message"),
    [
        ("   ", "needs a name"),
        ("x" * 41, "at most 40"),
        ("Indian, Kids", "comma"),
    ],
)
def test_bad_names_are_refused(typed, message):
    with pytest.raises(AdminError, match=message):
        normalise_category(typed)


def test_forty_characters_are_allowed():
    assert normalise_category("x" * 40) == "x" * 40


@pytest.mark.parametrize(
    ("name", "slug"),
    [
        ("Action Classics", "action-classics"),
        ("K-Drama!", "k-drama"),
        ("日本", "category"),
    ],
)
def test_slugs(name, slug):
    assert category_slug(name) == slug


# --- Admins ------------------------------------------------------------------


@pytest.fixture
def clean_categories(owner):
    """Only the seeds stay."""
    yield
    owner.execute("delete from public.categories where name <> all(%s)", (SEEDS,))


def put(api, admin, edition_id, names):
    return api.put(
        f"/api/v1/admin/editions/{edition_id}/categories",
        json={"names": names},
        headers=as_user(admin),
    )


@needs_database
def test_the_seeds_are_there(owner):
    names = [
        row[0] for row in owner.execute("select name from public.categories").fetchall()
    ]
    assert set(SEEDS) <= set(names)


@needs_database
def test_an_admin_sets_categories_matching_any_case(api, admin, clean_categories):
    made = draft(api, admin)

    response = put(
        api, admin, made["edition_id"], ["  indian ", "Bollywood  Hits", "KIDS", "kids"]
    )

    assert response.status_code == 200, response.text
    # Seeds keep their spelling; a new name keeps the admin's; repeats go.
    assert response.json()["categories"] == ["Indian", "Bollywood Hits", "Kids"]
    listed = api.get("/api/v1/admin/categories", headers=as_user(admin)).json()
    hits = next(c for c in listed if c["name"] == "Bollywood Hits")
    assert hits["slug"] == "bollywood-hits"
    assert hits["editions"] == 1
    # The most used first.
    assert listed[0]["editions"] == 1
    assert {c["name"] for c in listed} >= set(SEEDS)


@needs_database
def test_saving_again_replaces_them_in_order(api, admin, clean_categories):
    made = draft(api, admin)
    put(api, admin, made["edition_id"], ["Indian", "Kids"])

    response = put(api, admin, made["edition_id"], ["Korean", "Indian"])

    assert response.json()["categories"] == ["Indian", "Korean"]
    got = api.get(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
    ).json()
    assert got["categories"] == ["Indian", "Korean"]
    assert put(api, admin, made["edition_id"], []).json()["categories"] == []


@needs_database
@pytest.mark.parametrize(
    ("names", "message"),
    [
        ([f"Tag {n}" for n in range(11)], "at most 10 categories"),
        (["x" * 41], "at most 40 characters"),
        (["Indian, Kids"], "comma"),
        ([" "], "needs a name"),
    ],
)
def test_too_many_or_bad_names_are_refused(
    api, admin, clean_categories, names, message
):
    made = draft(api, admin)
    put(api, admin, made["edition_id"], ["Kids"])

    response = put(api, admin, made["edition_id"], names)

    assert response.status_code == 400
    assert message in response.json()["detail"]
    # Nothing changed.
    got = api.get(
        f"/api/v1/admin/editions/{made['edition_id']}", headers=as_user(admin)
    ).json()
    assert got["categories"] == ["Kids"]


@needs_database
def test_ten_is_allowed(api, admin, clean_categories):
    made = draft(api, admin)
    names = [f"Tag {n}" for n in range(10)]

    assert put(api, admin, made["edition_id"], names).json()["categories"] == names


@needs_database
def test_the_database_refuses_an_eleventh_too(owner, api, admin, clean_categories):
    made = draft(api, admin)
    put(api, admin, made["edition_id"], [f"Tag {n}" for n in range(10)])

    with pytest.raises(psycopg.errors.CheckViolation):
        owner.execute(
            "insert into public.edition_categories (edition_id, category_id) "
            "select %s, id from public.categories where name = 'Kids'",
            (made["edition_id"],),
        )


@needs_database
def test_a_name_differing_only_in_punctuation_gets_its_own_address(
    api, admin, clean_categories
):
    made = draft(api, admin)

    put(api, admin, made["edition_id"], ["Action-Classics"])

    listed = api.get("/api/v1/admin/categories", headers=as_user(admin)).json()
    slugs = {c["name"]: c["slug"] for c in listed}
    assert slugs["Action Classics"] == "action-classics"
    assert slugs["Action-Classics"] == "action-classics-2"


@needs_database
def test_an_unknown_edition_is_404(api, admin):
    assert put(api, admin, uuid.uuid4(), ["Kids"]).status_code == 404


@needs_database
def test_only_admins_set_or_list_categories(api, admin):
    stranger = as_user(uuid.uuid4())
    assert api.get("/api/v1/admin/categories", headers=stranger).status_code == 403
    response = api.put(
        f"/api/v1/admin/editions/{uuid.uuid4()}/categories",
        json={"names": ["Kids"]},
        headers=stranger,
    )
    assert response.status_code == 403


# --- Viewers -----------------------------------------------------------------


def tag(owner, edition_id, *names):
    for name in names:
        owner.execute(
            "insert into public.edition_categories (edition_id, category_id) "
            "select %s, id from public.categories where name = %s",
            (edition_id, name),
        )


@pytest.fixture
def tagged(owner, clean_categories):
    """Published RRR and Baahubali (Indian movies), Kabaka (an Indian
    series, for Kids too), a draft tagged Korean and a test film."""
    emmy = vj(owner, "VJ Emmy")
    made = {
        "rrr": title(owner, "RRR", vj_id=emmy, days_ago=2),
        "baahubali": title(owner, "Baahubali", vj_id=emmy, days_ago=5),
        "kabaka": title(owner, "Kabaka", vj_id=emmy, kind="series", days_ago=1),
        "plain": title(owner, "Plain", vj_id=emmy, days_ago=3),
    }
    tag(owner, made["rrr"], "Indian")
    tag(owner, made["baahubali"], "Indian")
    tag(owner, made["kabaka"], "Indian", "Kids")
    secret = title(owner, "Secret", vj_id=emmy)
    owner.execute(
        "update public.editions set status = 'draft' where id = %s", (secret,)
    )
    tag(owner, secret, "Korean")
    test_film = title(owner, "Test film", vj_id=emmy)
    owner.execute("update public.editions set test = true where id = %s", (test_film,))
    tag(owner, test_film, "Chinese")
    return made


@needs_database
def test_viewers_see_categories_with_published_titles(api, tagged):
    response = api.get("/api/v1/categories")

    assert response.status_code == 200
    assert response.json() == [
        {"slug": "indian", "name": "Indian", "editions": 3, "movies": 2},
        {"slug": "kids", "name": "Kids", "editions": 1, "movies": 0},
    ]


@needs_database
def test_editions_can_be_filtered_by_category(api, tagged):
    def titles(**params):
        response = api.get("/api/v1/editions", params=params)
        assert response.status_code == 200
        return [card["title"] for card in response.json()["editions"]]

    assert titles(category="indian") == ["Kabaka", "RRR", "Baahubali"]
    assert titles(category="indian", kind="movie") == ["RRR", "Baahubali"]
    assert titles(category="kids") == ["Kabaka"]
    # A draft's category matches nothing.
    assert titles(category="korean") == []
    assert titles(category="nothing-here") == []


@needs_database
def test_the_api_role_sees_only_published_links(app_url, tagged):
    with psycopg.connect(app_url) as conn:
        names = {
            row[0]
            for row in conn.execute("select name from public.categories").fetchall()
        }
        (links,) = conn.execute(
            "select count(*) from public.edition_categories"
        ).fetchone()

    # Chinese is on a published test film; Korean only on a draft.
    assert names == {"Indian", "Kids", "Chinese"}
    assert links == 5


@needs_database
def test_the_api_role_cant_change_categories(app_url, tagged):
    with psycopg.connect(app_url) as conn:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("insert into public.categories (name, slug) values ('X', 'x')")
