import { type Component } from "solid-js";

const LoadingSpinner: Component = () => {
  return (
    <div class="py-4">
      <div class="flex items-center justify-center">
        <div
          class="rounded-full h-8 w-8 border-2 border-gray-600 border-t-green-400"
          style="animation: spin 0.4s linear infinite;"
        ></div>
      </div>
    </div>
  );
};

export default LoadingSpinner;
