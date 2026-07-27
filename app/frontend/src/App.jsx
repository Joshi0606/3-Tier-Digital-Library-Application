import { useState, useEffect } from "react";

// Empty string = relative URL.
// Nginx proxies /auth/* /books/* /borrow/* to the correct backend.
const API_URL = "";

// ─────────────────────────────────────────────
// Dashboard — shown after login
// ─────────────────────────────────────────────
function Dashboard({ user, onSignOut }) {
  const [tab, setTab]         = useState("books");   // "books" | "myborrow"
  const [books, setBooks]     = useState([]);
  const [myBooks, setMyBooks] = useState([]);
  const [loadingBooks, setLoadingBooks]   = useState(false);
  const [loadingBorrow, setLoadingBorrow] = useState(false);
  const [msg, setMsg]         = useState({ text: "", type: "" });

  // Fetch all books on mount
  useEffect(() => {
    fetchBooks();
  }, []);

  // Fetch borrowed books whenever tab switches to myborrow
  useEffect(() => {
    if (tab === "myborrow") fetchMyBooks();
  }, [tab]);

  async function fetchBooks() {
    setLoadingBooks(true);
    try {
      const res  = await fetch(API_URL + "/books");
      const data = await res.json();
      setBooks(Array.isArray(data) ? data : []);
    } catch {
      setMsg({ text: "Could not load books.", type: "error" });
    } finally {
      setLoadingBooks(false);
    }
  }

  async function fetchMyBooks() {
    setLoadingBorrow(true);
    try {
      const res  = await fetch(`${API_URL}/borrow/mybooks/${user.id}`);
      const data = await res.json();
      setMyBooks(Array.isArray(data) ? data : []);
    } catch {
      setMsg({ text: "Could not load borrowed books.", type: "error" });
    } finally {
      setLoadingBorrow(false);
    }
  }

  async function borrowBook(bookId) {
    setMsg({ text: "", type: "" });
    try {
      const res = await fetch(API_URL + "/borrow", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: user.id, book_id: bookId }),
      });
      const data = await res.json();
      if (res.status === 201) {
        setMsg({ text: "Book borrowed successfully!", type: "success" });
      } else {
        setMsg({ text: data.error || "Could not borrow book.", type: "error" });
      }
    } catch {
      setMsg({ text: "Request failed.", type: "error" });
    }
  }

  return (
    <div className="dashboard-page">
      {/* ── Top nav ── */}
      <nav className="navbar">
        <div className="nav-brand">
          <div className="brand-mark">📚</div>
          <span className="brand-name">Digital Library</span>
        </div>
        <div className="nav-right">
          <span className="nav-user">👤 {user.name || user.email}</span>
          <button className="btn-signout" onClick={onSignOut}>Sign out</button>
        </div>
      </nav>

      <div className="dash-body">
        {/* ── Tab bar ── */}
        <div className="dash-tabs">
          <button
            className={"dash-tab" + (tab === "books" ? " active" : "")}
            onClick={() => setTab("books")}
          >
            📖 All Books
          </button>
          <button
            className={"dash-tab" + (tab === "myborrow" ? " active" : "")}
            onClick={() => setTab("myborrow")}
          >
            🔖 My Borrowed Books
          </button>
        </div>

        {/* ── Global message ── */}
        {msg.text && (
          <div className={"msg " + msg.type} style={{ maxWidth: 720, margin: "0 auto 16px" }}>
            {msg.text}
          </div>
        )}

        {/* ── All Books tab ── */}
        {tab === "books" && (
          <div className="book-grid">
            {loadingBooks && <p className="loading">Loading books…</p>}
            {!loadingBooks && books.length === 0 && (
              <p className="empty">No books found in the library.</p>
            )}
            {books.map((book) => (
              <div className="book-card" key={book.id}>
                <div className="book-icon">📗</div>
                <div className="book-info">
                  <div className="book-title">{book.title}</div>
                  <div className="book-author">by {book.author}</div>
                </div>
                <button
                  className="btn-borrow"
                  onClick={() => borrowBook(book.id)}
                >
                  Borrow
                </button>
              </div>
            ))}
          </div>
        )}

        {/* ── My Borrowed Books tab ── */}
        {tab === "myborrow" && (
          <div className="book-grid">
            {loadingBorrow && <p className="loading">Loading…</p>}
            {!loadingBorrow && myBooks.length === 0 && (
              <p className="empty">You haven't borrowed any books yet.</p>
            )}
            {myBooks.map((book, i) => (
              <div className="book-card" key={i}>
                <div className="book-icon">🔖</div>
                <div className="book-info">
                  <div className="book-title">{book.title}</div>
                  <div className="book-author">by {book.author}</div>
                  <div className="book-date">
                    Borrowed: {new Date(book.borrow_date).toLocaleDateString()}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────
// Auth form — signin / signup
// ─────────────────────────────────────────────
export default function App() {
  const [mode, setMode]       = useState("signin");
  const [name, setName]       = useState("");
  const [email, setEmail]     = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState({ text: "", type: "" });
  const [loading, setLoading] = useState(false);
  const [user, setUser]       = useState(null);

  // Restore session from localStorage
  useEffect(() => {
    const saved = localStorage.getItem("library_user");
    if (saved) {
      try { setUser(JSON.parse(saved)); }
      catch { localStorage.removeItem("library_user"); }
    }
  }, []);

  function switchTab(target) {
    setMode(target);
    setMessage({ text: "", type: "" });
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setMessage({ text: "", type: "" });

    if (mode === "signup" && !name.trim()) {
      setMessage({ text: "Please enter your full name.", type: "error" });
      return;
    }

    setLoading(true);
    try {
      const endpoint = mode === "signin" ? "/auth/signin" : "/auth/signup";
      const body     = mode === "signin"
        ? { email, password }
        : { name, email, password };

      const res  = await fetch(API_URL + endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();

      if (mode === "signin") {
        if (res.ok && data.user_id) {
          const loggedInUser = { id: data.user_id, name: data.name, email };
          localStorage.setItem("library_user", JSON.stringify(loggedInUser));
          setTimeout(() => setUser(loggedInUser), 300);
        } else {
          setMessage({ text: data.message || data.error || "Invalid credentials.", type: "error" });
        }
      } else {
        if (res.status === 201) {
          setMessage({ text: "Account created. You can now sign in.", type: "success" });
          setTimeout(() => switchTab("signin"), 900);
        } else {
          setMessage({ text: data.error || "Could not create account.", type: "error" });
        }
      }
    } catch {
      setMessage({ text: "Couldn't reach the server.", type: "error" });
    } finally {
      setLoading(false);
    }
  }

  function signOut() {
    localStorage.removeItem("library_user");
    setUser(null);
    setName(""); setEmail(""); setPassword("");
    setMode("signin");
  }

  // Show dashboard if logged in
  if (user) return <Dashboard user={user} onSignOut={signOut} />;

  // Show auth form
  return (
    <div className="page">
      <div className="card">
        <div className="brand">
          <div className="brand-mark">📚</div>
          <div className="brand-name">Digital Library</div>
        </div>

        <div className="tabs">
          <div className={"tab" + (mode === "signin" ? " active" : "")} onClick={() => switchTab("signin")}>
            Sign in
          </div>
          <div className={"tab" + (mode === "signup" ? " active" : "")} onClick={() => switchTab("signup")}>
            Create account
          </div>
        </div>

        <h1>{mode === "signin" ? "Welcome back" : "Create your account"}</h1>
        <p className="sub">
          {mode === "signin" ? "Sign in to your account" : "Join the library in a few seconds"}
        </p>

        <form onSubmit={handleSubmit}>
          {mode === "signup" && (
            <>
              <label htmlFor="name">Full name</label>
              <input id="name" type="text" placeholder="Jane Doe" autoComplete="name"
                value={name} onChange={(e) => setName(e.target.value)} />
            </>
          )}

          <label htmlFor="email">Email</label>
          <input id="email" type="email" placeholder="you@example.com" autoComplete="email"
            required value={email} onChange={(e) => setEmail(e.target.value)} />

          <label htmlFor="password">Password</label>
          <input id="password" type="password" placeholder="••••••••" autoComplete="current-password"
            required value={password} onChange={(e) => setPassword(e.target.value)} />

          <button type="submit" className="submit" disabled={loading}>
            {loading
              ? (mode === "signin" ? "Signing in…" : "Creating account…")
              : (mode === "signin" ? "Sign in" : "Create account")}
          </button>

          {message.text && <div className={"msg " + message.type}>{message.text}</div>}
        </form>
      </div>
    </div>
  );
}
