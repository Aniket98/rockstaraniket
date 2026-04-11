---
layout: default
title: General Theory of RDBMS
---

## General Theory of RDBMS

All the RDBMS conceptually work similarly.
Working on a single database primarily brainwashes the brain.

{% assign filtered_posts = site.posts | where_exp: "p", "p.tags contains 'gtrdbms'" %}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No posts yet.
{% endif %}
