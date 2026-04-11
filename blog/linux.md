---
layout: default
title: Linux Posts
---

## Linux Posts

{% assign filtered_posts = site.posts | where_exp: "p", "p.tags contains 'linux'" %}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No posts yet.
{% endif %}
