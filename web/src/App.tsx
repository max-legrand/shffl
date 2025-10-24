import {
  type Component,
  onMount,
  createSignal,
  Switch,
  Match,
  Show,
  createEffect,
  For,
} from "solid-js";
import LoadingSpinner from "./LoadingSpinner";
import GitHubLink from "./GitHubLink";

const UNAUTHORIZED = 401;

const App: Component = () => {
  const [user, setUser] = createSignal<string | null>(null);
  const [name, setName] = createSignal<string | null>(null);
  const [playlists, setPlaylists] = createSignal<any[]>([]);
  const [isLoading, setIsLoading] = createSignal(false);
  const [hasMore, setHasMore] = createSignal(true);
  const [nextOffset, setNextOffset] = createSignal(0);
  const [initialized, setInitialized] = createSignal(false);
  const LIMIT = 50;
  let scrollContainer: HTMLDivElement | undefined = undefined;

  const [queueProgress, setQueueProgress] = createSignal<{
    current: number;
    total: number;
  } | null>(null);
  const [queueError, setQueueError] = createSignal<string | null>(null);

  const queuePlaylist = (playlistId: string) => {
    setQueueProgress({ current: 0, total: 0 });
    const eventSource = new EventSource(`/queue-playlist/${playlistId}`);

    eventSource.onopen = () => {
      console.log("EventSource connection opened");
    };

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.complete) {
          eventSource.close();
          setTimeout(() => setQueueProgress(null), 500);
        } else {
          setQueueProgress(data);
        }
      } catch (e) {
        console.error("Failed to parse progress:", e);
        console.error("Raw event data was:", event.data);
      }
    };

    eventSource.onerror = (err) => {
      console.error("EventSource error:", err);
      console.log("EventSource readyState:", eventSource.readyState);
      eventSource.close();
      setQueueProgress(null);
      setQueueError("Failed to queue tracks. Please try again.");
    };
  };

  const checkLoginStatus = async () => {
    try {
      const cached = localStorage.getItem("user");
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed.error) {
          localStorage.removeItem("user");
          setUser(null);
          return;
        }
        setUser(cached);
        return;
      }

      const response = await fetch("/user");
      if (response.status == UNAUTHORIZED || !response.ok) {
        localStorage.removeItem("user");
        setUser(null);
        return;
      }
      const data_text = await response.text();
      const parsed = JSON.parse(data_text);
      if (parsed.error) {
        localStorage.removeItem("user");
        setUser(null);
        return;
      }
      localStorage.setItem("user", data_text);
      setUser(data_text);
    } catch (error) {
      console.error("Failed to check login status:", error);
      localStorage.removeItem("user");
      setUser(null);
    }
  };

  onMount(() => {
    checkLoginStatus();
  });

  const loadMorePlaylists = async (offset: number) => {
    if (isLoading()) return;

    setIsLoading(true);
    try {
      const response = await fetch(
        `/playlists?offset=${offset}&limit=${LIMIT}`,
      );
      const data = await response.json();

      if (!data.items || data.items.length === 0) {
        setHasMore(false);
        setIsLoading(false);
        return;
      }

      let allPlaylists = data.items;

      const sorted = allPlaylists.sort((a: any, b: any) => {
        const dateA = a.modified_at ? new Date(a.modified_at).getTime() : 0;
        const dateB = b.modified_at ? new Date(b.modified_at).getTime() : 0;
        return dateB - dateA;
      });

      const newOffset = offset + data.items.length;
      setPlaylists([...playlists(), ...sorted]);
      setNextOffset(newOffset);
      setHasMore(newOffset < data.total);
    } catch (error) {
      console.error("Failed to load playlists:", error);
    } finally {
      setIsLoading(false);
    }
  };

  let scrollTimeout: ReturnType<typeof setTimeout>;
  const handleScroll = () => {
    if (!scrollContainer || isLoading() || !hasMore()) return;

    clearTimeout(scrollTimeout);
    scrollTimeout = setTimeout(() => {
      const { scrollTop, scrollHeight, clientHeight } = scrollContainer!;
      if (scrollHeight - scrollTop - clientHeight < 500) {
        loadMorePlaylists(nextOffset());
      }
    }, 200);
  };

  createEffect(() => {
    const currentUser = user();
    if (currentUser !== null && !initialized()) {
      const data = JSON.parse(currentUser);
      setName(data.display_name);
      setInitialized(true);
      loadMorePlaylists(0);
    } else if (currentUser === null) {
      setPlaylists([]);
      setHasMore(true);
      setNextOffset(0);
      setInitialized(false);
    }
  });

  function login() {
    window.location.href = "/login";
  }

  async function logout() {
    localStorage.removeItem("user");
    setUser(null);
    setPlaylists([]);
    setInitialized(false);
    await fetch("/logout");
    window.location.href = "/";
  }

  return (
    <div
      class="h-full w-full bg-gray-900 overflow-hidden flex flex-col"
      style={{
        "padding-top": "env(safe-area-inset-top)",
        "padding-bottom": "env(safe-area-inset-bottom)",
      }}
    >
      <Switch>
        <Match when={user() === null}>
          <div class="flex items-center justify-center h-full flex-1">
            <div class="text-center">
              <p class="text-6xl text-green-400 mb-2">Shffl</p>
              <p class="text-2xl text-gray-400 mb-8">
                Truly randomize your Spotify playlists
              </p>
              <button
                class="bg-green-400 hover:bg-green-500 text-black font-bold py-3 px-8 rounded-lg text-lg transition"
                onClick={() => {
                  login();
                }}
              >
                Log in with Spotify
              </button>
              <br />
              <p class="text-gray-400 text-s mt-8 flex items-center justify-center gap-2">
                Check out the source code on <GitHubLink full />
              </p>
            </div>
          </div>
        </Match>
        <Match when={user() !== null}>
          <div class="flex flex-col h-full flex-1">
            <div
              class="shrink-0 bg-linear-to-r from-green-400 to-green-500 text-black px-4 py-3 sm:px-8 flex items-center justify-between"
              style={{
                "padding-top": "calc(env(safe-area-inset-top) + 0.4rem)",
              }}
            >
              <div>
                <p class="text-4xl font-bold">Shffl</p>
                <p class="text-s opacity-90">Logged in as {name()}</p>
              </div>
              <button
                onClick={logout}
                class="bg-black hover:bg-green-700 text-white font-semibold py-1 px-4 rounded text-sm transition"
              >
                Logout
              </button>
            </div>

            <div class="flex-1 overflow-hidden p-4 sm:p-8 flex flex-col">
              <Show when={playlists().length === 0 && isLoading()}>
                <div class="flex items-center justify-center h-full">
                  <LoadingSpinner />
                </div>
              </Show>
              <Show when={playlists().length > 0 || !isLoading()}>
                <div class="flex flex-col h-full">
                  <div class="flex items-center justify-between mb-6">
                    <h2 class="text-white text-2xl font-bold">
                      Your Playlists ({playlists().length})
                    </h2>
                    <GitHubLink />
                  </div>
                  <div
                    ref={scrollContainer}
                    onScroll={handleScroll}
                    class="flex-1 overflow-y-auto pb-8"
                    style={{ "padding-bottom": "env(safe-area-inset-bottom)" }}
                  >
                    <div class="p-4">
                      <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 2xl:grid-cols-7 gap-4">
                        <For each={playlists()}>
                          {(playlist) => (
                            <div
                              class="bg-gray-800 rounded-lg overflow-hidden hover:bg-green-500 hover:scale-105 transition-all duration-150 cursor-pointer group relative"
                              onClick={() => {
                                queuePlaylist(playlist.id);
                              }}
                            >
                              <div class="aspect-square bg-gray-700 overflow-hidden">
                                {playlist.images &&
                                playlist.images.length > 0 ? (
                                  <img
                                    src={playlist.images[0].url}
                                    alt={playlist.name}
                                    class="w-full h-full object-cover"
                                  />
                                ) : (
                                  <div class="w-full h-full flex items-center justify-center">
                                    <p class="text-gray-500 text-xs">
                                      No image
                                    </p>
                                  </div>
                                )}
                              </div>
                              <div class="p-2">
                                <p class="text-white font-semibold text-xs truncate group-hover:text-black">
                                  {playlist.name}
                                </p>
                                <p class="text-gray-400 text-xs mt-1 group-hover:text-black">
                                  {playlist.tracks.total} tracks
                                </p>
                              </div>
                            </div>
                          )}
                        </For>
                      </div>
                    </div>
                    <Show when={isLoading()}>
                      <div class="flex justify-center py-8">
                        <LoadingSpinner />
                      </div>
                    </Show>
                  </div>
                </div>
              </Show>
            </div>
          </div>
        </Match>
      </Switch>

      <Show when={queueProgress() !== null}>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
          style={{
            "padding-top": "env(safe-area-inset-top)",
            "padding-bottom": "env(safe-area-inset-bottom)",
          }}
        >
          <div class="bg-gray-800 rounded-lg p-8 text-center max-w-sm">
            <LoadingSpinner />
            <p class="text-white text-lg font-semibold mt-4">
              Queuing tracks...
            </p>
            <Show when={queueProgress()?.total && queueProgress()!.total > 0}>
              <p class="text-gray-300 mt-2">
                {queueProgress()?.current} / {queueProgress()?.total}
              </p>
              <div class="w-full bg-gray-700 rounded-full h-2 mt-4">
                <div
                  class="bg-green-400 h-2 rounded-full transition-all duration-300"
                  style={{
                    width: `${((queueProgress()?.current || 0) / (queueProgress()?.total || 1)) * 100}%`,
                  }}
                />
              </div>
            </Show>
          </div>
        </div>
      </Show>

      <Show when={queueError() !== null}>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
          style={{
            "padding-top": "env(safe-area-inset-top)",
            "padding-bottom": "env(safe-area-inset-bottom)",
          }}
        >
          <div class="bg-gray-800 rounded-lg p-8 text-center max-w-sm">
            <p class="text-red-400 text-2xl font-bold mb-4">⚠️</p>
            <p class="text-white text-lg font-semibold mb-6">{queueError()}</p>
            <button
              onClick={() => setQueueError(null)}
              class="bg-green-400 hover:bg-green-500 text-black font-bold py-2 px-6 rounded-lg transition"
            >
              Close
            </button>
          </div>
        </div>
      </Show>
    </div>
  );
};

export default App;
