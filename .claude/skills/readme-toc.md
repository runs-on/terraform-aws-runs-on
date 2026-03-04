# Skill: Generate README Table of Contents

Generate or update the table of contents in the README.md file.

## Instructions

1. Read the README.md file in the project root
2. Extract all headings (lines starting with `#`, `##`, `###`)
3. Skip the main title (first `#` heading) and the "Table of Contents" section itself
4. Generate a markdown table of contents with:
   - Proper indentation (2 spaces per level, starting from `##` as top level)
   - GitHub-compatible anchor links (lowercase, spaces to hyphens, remove special characters like parentheses)
   - Nested structure reflecting heading hierarchy
5. Replace the existing "Table of Contents" section content (between `## Table of Contents` and the next `##` heading)
6. If no "Table of Contents" section exists, add one after the first paragraph (after the main title and description)

## Anchor Link Rules for GitHub

- Convert to lowercase
- Replace spaces with hyphens (`-`)
- Remove parentheses and other special characters
- Example: `### WAF (Web Application Firewall)` becomes `#waf-web-application-firewall`

## Output Format

```markdown
## Table of Contents

- [Section Name](#section-name)
  - [Subsection](#subsection)
    - [Sub-subsection](#sub-subsection)
```

## Notes

- Do not include headings inside code blocks (between triple backticks)
- Do not include headings inside the `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` auto-generated section when determining structure (but DO include those headings in the TOC)
- Preserve any existing content before and after the Table of Contents section
