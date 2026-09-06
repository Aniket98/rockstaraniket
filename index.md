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

## Latest Posts of the Last 3 Months

{% assign current_year = site.time | date: "%Y" | plus: 0 %}
{% assign current_month = site.time | date: "%m" | plus: 0 %}

{% assign filtered_posts = "" | split: "" %}

{% for post in site.posts %}
  {% assign post_year = post.date | date: "%Y" | plus: 0 %}
  {% assign post_month = post.date | date: "%m" | plus: 0 %}

  {% assign current_total_months = current_year | times: 12 | plus: current_month %}
  {% assign post_total_months = post_year | times: 12 | plus: post_month %}
  {% assign month_difference = current_total_months | minus: post_total_months %}

  {% if month_difference >= 0 and month_difference < 3 %}
    {% unless post.tags and post.tags contains 'wip' %}
      {% assign filtered_posts = filtered_posts | push: post %}
    {% endunless %}
  {% endif %}
{% endfor %}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No new posts in the last 3 months. You can search older posts from top navigation panel.
{% endif %}
