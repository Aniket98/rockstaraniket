// The Password Curtain .js

const TOKEN_KEY = "site_auth_expiry";
//const TOKEN_DURATION = 12 * 60 * 60 * 1000;
const TOKEN_DURATION = 30 * 1000;
const hashedPassword = "6bd2379ddf3baef6ac7f5f65b4a51c07";

const input = document.getElementById('passwordInput');
const validationDiv = document.getElementById('password-validation');
const protectedDiv = document.getElementById('protected');

function setToken() {
  const expiry = Date.now() + TOKEN_DURATION;
  localStorage.setItem(TOKEN_KEY, expiry);
}

function isTokenValid() {
  const expiry = localStorage.getItem(TOKEN_KEY);
  return expiry && Date.now() < expiry;
}

function unlock() {
  validationDiv.classList.add('slide-left');
  protectedDiv.style.display = "block";  // show first

  setTimeout(() => {
    protectedDiv.classList.add('slide-up'); // then animate
  }, 10);

  setTimeout(() => {
    document.getElementById('old-content')?.remove();
  }, 600);
}

function autoUnlockAnimation() {
  const fake = Math.random().toString(36).slice(-8);
  let i = 0;

  input.disabled = true;
  input.focus();

  const typer = setInterval(() => {
    input.value += fake[i];
    i++;

    if (i >= fake.length) {
      clearInterval(typer);
      setTimeout(unlock, 300);
    }
  }, 40);
}
//Manual Reset Token: localStorage.removeItem("site_auth_expiry");

function checkPassword() {
  const value = input.value.trim();
  const hash = CryptoJS.MD5(value).toString();

  if (hash === hashedPassword) {
    setToken();
    unlock();
  } else {
    input.value = '';
    input.classList.add('shake');
    setTimeout(() => input.classList.remove('shake'), 1000);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  if (isTokenValid()) {
    setTimeout(autoUnlockAnimation, 1000);
    return;
  }

  input.focus();
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter') checkPassword();
  });
});

