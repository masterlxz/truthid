import { Component, type ReactNode } from "react";
import i18n from "../i18n";

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: "2rem", color: "var(--color-danger, #ef4444)" }}>
          <h2>{i18n.t("errorBoundary.title")}</h2>
          <pre style={{ whiteSpace: "pre-wrap", fontSize: "0.85rem", opacity: 0.8 }}>
            {this.state.error.message}
          </pre>
          <button onClick={() => this.setState({ error: null })}>{i18n.t("errorBoundary.tryAgain")}</button>
        </div>
      );
    }
    return this.props.children;
  }
}
