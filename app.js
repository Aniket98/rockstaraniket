window.addEventListener('DOMContentLoaded', function () {
  const input = document.getElementById('passwordInput');
  const validationDiv = document.getElementById('password-validation');
  const triangleDiv = document.querySelector('.triangle');
  let protectedDiv = document.getElementById('protected');

  // MD5("aniketkk")
  const hashedPassword = "42e8a08acfe909950e564c3fb50cc632";

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
      })
      .catch(err => {
        protectedDiv.innerHTML = '<p>⚠️ Could not load protected content.</p>';
        console.error(err);
      });
  }

  function unlock() {
    let handled = false;

    const onAnimEnd = () => {
      if (handled) return;
      handled = true;
      loadProtectedHtml();
    };

    if (triangleDiv) {
      triangleDiv.addEventListener('animationend', onAnimEnd, { once: true });
      setTimeout(() => {
        if (!handled) {
          handled = true;
          loadProtectedHtml();
        }
      }, 600);
    }

    validationDiv.classList.add('slide-left');
    triangleDiv.classList.add('slide-right');
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
