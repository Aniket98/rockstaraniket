---
layout: default
title: Misc Articles
---

## Misc Articles

{% assign filtered_posts = site.posts | where_exp: "p", "p.tags contains 'misc'" %}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No posts yet.
{% endif %}

