// Global path variable
let $path = '';

  const navBar = document.getElementById('navBar');
  const leftPanel = document.getElementById('leftPanel');

  // Add click listener for all spans inside navBar
  navBar.querySelectorAll('span').forEach(span => {
    span.addEventListener('click', () => {
      const name = span.textContent.trim();
      if (!name) return; // skip empty spans


      // 1️⃣ Clear leftPanel
      leftPanel.innerHTML = '';

      // 2️⃣ Set global path
      $path = `database/${name}/`;

      // 3️⃣ Load left.html from that path
      fetch(`${$path}left.html`, { cache: 'no-store' })
        .then(res => {
          if (!res.ok) throw new Error('Failed to load left.html');
          return res.text();
        })
        .then(html => {
          leftPanel.innerHTML = html;
        })
        .catch(err => {
          leftPanel.innerHTML = `<p style="color:red;">⚠️ Could not load content.</p>`;
          console.error(err);
        });
    });
  });

// After attaching click listeners, Do First AutoClick
const homeSpan = document.querySelector('#navBar span'); // first span is Home
if (homeSpan) homeSpan.click(); // simulate click on page load