import { type Component } from "solid-js";

interface GitHubLinkProps {
  full?: boolean;
  href?: string;
}

const GitHubLink: Component<GitHubLinkProps> = (props) => {
  const href = props.href || "https://github.com/max-legrand/shffl";
  const full = props.full ?? false;

  return (
    <a
      href={href}
      target="_blank"
      class="text-gray-400 hover:text-green-400 transition flex items-center gap-2"
    >
      <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
        <path
          fill-rule="evenodd"
          d="M10 0C4.477 0 0 4.484 0 10c0 4.42 2.865 8.17 6.839 9.49.5.092.682-.217.682-.482 0-.237-.008-1.022-.012-2.005-2.782.603-3.369-1.343-3.369-1.343-.454-1.156-1.11-1.463-1.11-1.463-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.087 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0 1 10 4.817c.85.004 1.705.114 2.504.336 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C17.138 18.163 20 14.413 20 10c0-5.516-4.477-10-10-10z"
          clip-rule="evenodd"
        />
      </svg>
      {full && <span>GitHub</span>}
    </a>
  );
};

export default GitHubLink;
