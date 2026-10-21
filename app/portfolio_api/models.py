"""The published content, as the API serves it.

This is the shape written by `scripts/check_content.py --build`: approved lines only, no
approval flags. Unknown fields are rejected, so the build and the API cannot drift apart
without a test failing.
"""

from pydantic import BaseModel, ConfigDict


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Profile(_Model):
    # Every line is optional: only approved lines are published.
    name: str | None = None
    title: str | None = None
    summary: str | None = None
    country: str | None = None


class Link(_Model):
    label: str
    url: str


class SkillGroup(_Model):
    category: str
    items: list[str]


class Experience(_Model):
    employer: str
    role: str
    start: str
    end: str
    bullets: list[str]


class Section(_Model):
    heading: str
    paragraphs: list[str]


class CaseStudy(_Model):
    id: str
    title: str
    summary: str
    sections: list[Section]


class Content(_Model):
    version: int
    profile: Profile
    links: list[Link]
    skills: list[SkillGroup]
    experience: list[Experience]
    case_studies: list[CaseStudy]
    languages: list[str]
