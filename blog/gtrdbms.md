---
layout: default
title: General Theory of RDBMS
---

## General Theory of RDBMS

All RDBMS follow a similar high-level flow like accept connections, authenticate users, allocate resources, and execute SQL queries, but differ significantly in how these steps are implemented internally.

For example: The PostgreSQL database prefers to assign a dedicated OS PROCESS to a user session (instead of thread).
Similarly, in Oracle (with dedicated server mode + threaded_execution:false) on Linux, assigns a dedicated OS process to a session, while shared server configuration uses a shared pool of server processes.

But MySQL and SQL Server do different.

MySQL assigns a THREAD (instead of OS Process) to a user session.
And SQL server uses a POOL of worker threads, where tasks from sessions are scheduled onto available threads by SOS scheduler rather than having a dedicated thread per session.

SQL Server might feel a bit complex at first to understand.
Below are 2 links that can help:
- [Link 1](https://learn.microsoft.com/en-us/sql/relational-databases/thread-and-task-architecture-guide?view=sql-server-ver17)
- [Link 2](https://www.sqlservercentral.com/blogs/memory-fundamentals-for-sql-server-process-thread-model-cpu-execution-model-cpu-scheduling-cpu-architechture-sqlos)

But why all these differences? Well, each has their own benefit and disadvantage. And each database was designed focusing on specific goals more. This leads to few distinctions in their design and implementations.

Which is best? It depends on what fits your need more.
Each database comes with their own unique strengths along with tradeoffs (ofter termed as disadvantages, but better look at them as tradeoffs).

Working only on a single database often leads to the thinking that 1 database is best.
But that is an emotional judgement, saying one database is best.

The truth is each database has their own unique design benefits.

That's why it becomes very important to look at the RDBMS from an Un-biased mindset.

Internally, you should not fight over which database is best.
Instead as a DBA, one should learn the powers and gaps of each database and be able to administer them.

To achieve this ADMINISTRATION of all 4 databases at once, we need an Un-Biased Database Theory.
I give this theory the name "General Theory of RDBMS".

Initially, the focus on this general theory would be more towards a Troubleshooting Mindset, so it becomes possible to learn & be able to admnister the databases comparitively faster. In between (& later), as opportunity comes, this general theory will also extend trying to go deeper from a Design Mindset as well.

Below, the GT-RDBMS posts have been listed and will keep adding on:

### GT-RDBMS Posts

{% assign filtered_posts = site.posts | where_exp: "p", "p.tags contains 'gtrdbms'" %}

{% if filtered_posts.size > 0 %}
{% for post in filtered_posts %}
- [{{ post.title }}]({{ post.url }})
{% endfor %}
{% else %}
No posts yet.
{% endif %}


#### --------------------------------------------------
