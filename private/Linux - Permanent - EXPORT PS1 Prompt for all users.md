# Linux - Permanent - EXPORT PS1 Prompt for all users

On Rocky Linux:
|_ vi /etc/bashrc
	add in last: export PS1="\u@\h:\w\$ "

## What is export PS1="\u@\h:\w\$ "?

### Component Breakdown

* **`export PS1=`** – Defines and applies the primary prompt string globally to the session.
* **`\u`** – **Username** of the active user.
* **`@`** – Literal separator text.
* **`\h`** – **Hostname** / machine name.
* **`:`** – Literal separator text.
* **`\w`** – **Current path** (absolute directory layout; home is abbreviated as `~`).
* **`\$`** – Contextual privilege symbol (**`$`** for standard user, **`#`** for root).
* **` `** – Trailing space for readability before typed commands.

### Output Example
```text
user@server:~/var/folder$
```
