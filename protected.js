// Global path variable
let $path = '';

const navBar = document.getElementById('navBar');
const leftPanel = document.getElementById('leftPanel');
const displayScreen = document.getElementById('displayScreen');

// --- Function to handle nav bar click ---
function handleNavClick(span) {
  const name = span.textContent.trim();
  if (!name) return;

  // 1️⃣ Clear leftPanel
  leftPanel.innerHTML = '';
  displayScreen.innerHTML = '';

  // 2️⃣ Set global path
  $path = `database/${name}/`;

  // 3️⃣ Load left.html into leftPanel
  fetch(`${$path}left.html`, { cache: 'no-store' })
    .then(res => {
      if (!res.ok) throw new Error('Failed to load left.html');
      return res.text();
    })
    .then(html => {
      leftPanel.innerHTML = html;

      // Attach click listeners to <li> items
      const liItems = leftPanel.querySelectorAll('li');
      liItems.forEach(li => {
        li.addEventListener('click', () => {
          const liName = li.textContent.trim();
          if (!liName) return;

          // Clear displayScreen before loading new content
          displayScreen.innerHTML = '';

          const liPath = `${$path}${liName}.html`;
          fetch(liPath, { cache: 'no-store' })
            .then(res => {
              if (!res.ok) throw new Error(`Failed to load ${liName}.html`);
              return res.text();
            })
            .then(html => {
              displayScreen.innerHTML = html;
            })
            .catch(err => {
              displayScreen.innerHTML = `<p style="color:red;">⚠️ Could not load ${liName}.html</p>`;
              console.error(err);
            });
        });
      });

      // Auto-click first <li> if exists
      if (liItems.length > 0) liItems[0].click();
    })
    .catch(err => {
      leftPanel.innerHTML = `<p style="color:red;">⚠️ Could not load left.html</p>`;
      console.error(err);
    });
}

// --- Attach click listeners to nav bar spans ---
navBar.querySelectorAll('span').forEach(span => {
  span.addEventListener('click', () => handleNavClick(span));
});

// --- Auto-click first nav bar item (Home) ---
const firstNavSpan = navBar.querySelector('span');
if (firstNavSpan) firstNavSpan.click();
