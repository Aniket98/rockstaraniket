window.addEventListener('DOMContentLoaded', function () {
  const input = document.getElementById('passwordInput');
  const validationDiv = document.getElementById('password-validation');
  const triangleDiv = document.querySelector('.triangle');
  let protectedDiv = document.getElementById('protected');

unlock();

  // MD5 of your password
  const hashedPassword = "766786aaf872f77ef6f467d3fccd3248";

  function ensureProtectedDiv() {
    if (!protectedDiv) {
      protectedDiv = document.createElement('div');
      protectedDiv.id = 'protected';
      triangleDiv.insertAdjacentElement('afterend', protectedDiv);
    }
  }

function loadProtectedHtml() {
  ensureProtectedDiv();
  fetch('protected.html', { cache: 'no-store' })
    .then(r => {
      if (!r.ok) throw new Error('Failed to load protected.html');
      return r.text();
    })
    .then(html => {
      protectedDiv.innerHTML = html;
      protectedDiv.classList.add('slide-up');

      // Remove old content after animation
setTimeout(() => {
  const oldContent = document.getElementById('old-content');
  if (oldContent) oldContent.remove();

  // Dynamically add new CSS for protected content
  const newCss = document.createElement('link');
  newCss.rel = 'stylesheet';
  newCss.href = 'protected.css'; // <-- your new CSS file
  newCss.type = 'text/css';

  // Optional: remove old CSS
  const oldCss = document.querySelector('link[href="style.css"]');
  if (oldCss) oldCss.remove();

  document.head.appendChild(newCss);
  
}, 100); // after slide animation
    })
    .catch(err => {
      protectedDiv.innerHTML = '<p>⚠️ Could not load protected content.</p>';
      console.error(err);
    });
}

  function unlock() {
    // Slide old content out
    validationDiv.classList.add('slide-left');

    // Load new content
    loadProtectedHtml();
  }

  function checkPassword() {
    const value = input.value.trim();
    const hash = CryptoJS.MD5(value).toString();

    if (hash === hashedPassword) {
      unlock();
    } else {
      input.value = '';
      input.classList.add('shake');
      setTimeout(() => input.classList.remove('shake'), 1000);
      input.focus();
    }
  }

input.focus();
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') checkPassword();
  });
});
