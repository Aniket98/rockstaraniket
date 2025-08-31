    window.addEventListener('DOMContentLoaded', function () {
      const input = document.getElementById('passwordInput');
      const validationDiv = document.getElementById('password-validation');
      const triangleDiv = document.querySelector('.triangle');
      const protectedDiv = document.getElementById('protected');

      const hashedPassword = "42e8a08acfe909950e564c3fb50cc632";

      function checkPassword() {
        const value = input.value.trim();
        const inputHash = CryptoJS.MD5(value).toString();

        if (inputHash === hashedPassword) {
          validationDiv.classList.add('slide-left');
          triangleDiv.classList.add('slide-right');

          triangleDiv.addEventListener('animationend', () => {
            protectedDiv.innerHTML = "<h1>Welcome!</h1><p>Protected content revealed 🎉</p>";
            protectedDiv.classList.add('slide-up');
          }, { once: true });

        } else {
	  input.value = "";   // clear the input
          input.classList.add('shake');
          setTimeout(() => input.classList.remove('shake'), 1000);
        }
      }

      // Enter key
      input.addEventListener('keydown', e => {
        if (e.key === 'Enter') checkPassword();
      });

    });

