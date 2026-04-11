---
title: Home
---

## About Me

I am Aniket Tomar.

The databases fascinate me. Their architectures. Their workings. Their administration.
I had a dream in year 2021. To learn & administer 4 databases all at once.

Namely: Oracle, SQL Server, PostgreSQL, MySQL.

To complete this dream, I recently started to create a theory that develops a new vision.
A vision that activates a viewpoint to look at these 4 databaes in a complete unique way!

I name this theory "General Theory of RDBMS".
You can learn more here [GT-RDBMS](/blog/gtrdbms.html).

## Motive of this website

This is my personal knowledge base covering OS, Databases & Networking internals.

Life should be simple, not messy.  
Simple. Neat. But powerful.

As a person, its a habit to learn something, feel great and move on, but not document it.  
Not documenting feels easy, but impacts the very near future and not just long distant future.

Result? Need to search all things again, re-verify, re-test.
Pure wastage of time and efforts.

The motive is to learn something once, properly, and document it.  
And whenever needed, quickly reference this knowledge base and move to next topics swiftly.

## Latest Posts of this Month

{% assign now_month = site.time | date: "%Y-%m" %}

{% assign filtered_posts = site.posts
  | where_exp: "p", "p.date | date: '%Y-%m' == now_month"
%}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No posts in this month. You can search older posts from top navigation panel.
{% endif %}
