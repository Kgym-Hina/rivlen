import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App.jsx";
import GatewayGuide from "./GatewayGuide.jsx";
import "./styles.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    {window.location.pathname.replace(/\/$/, "") === "/gateway" ? <GatewayGuide /> : <App />}
  </React.StrictMode>,
);
