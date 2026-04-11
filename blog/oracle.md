---
layout: default
title: Oracle Database Posts
---

{% for post in site.posts %}
  {% if post.tags contains "oracle" %}
    - [{{ post.title }}]({{ post.url }})
  {% endif %}
{% endfor %}