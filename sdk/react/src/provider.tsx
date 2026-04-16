import { createClient, type CachePuppyClient, type ClientOptions, type ConnectionState } from "cachepuppy-js-sdk";
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

type ProviderValue = {
  client: CachePuppyClient;
  state: ConnectionState;
  error: Error | null;
  connect: () => Promise<void>;
  disconnect: (reason?: string) => Promise<void>;
  destroy: () => Promise<void>;
};

const CachePuppyContext = createContext<ProviderValue | null>(null);

export interface CachePuppyProviderProps {
  options: ClientOptions;
  autoConnect?: boolean;
  children: ReactNode;
}

export function CachePuppyProvider({ options, autoConnect = false, children }: CachePuppyProviderProps) {
  const client = useMemo(
    () => createClient(options),
    [
      options.url,
      options.clientId,
      options.authToken,
      options.getAuthToken,
      options.transport,
      options.reconnect?.enabled,
      options.reconnect?.initialDelayMs,
      options.reconnect?.maxDelayMs,
      options.reconnect?.factor,
    ],
  );
  const [state, setState] = useState<ConnectionState>(client.getState());
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    setState(client.getState());
    setError(null);
  }, [client]);

  useEffect(() => {
    const offState = client.on("stateChange", ({ state: nextState }) => {
      setState(nextState);
    });
    const offError = client.on("error", (err) => {
      setError(err);
    });

    return () => {
      offState();
      offError();
    };
  }, [client]);

  useEffect(() => {
    if (!autoConnect) {
      return;
    }
    void client.connect().catch((err: unknown) => {
      setError(err instanceof Error ? err : new Error("Failed to connect"));
    });
  }, [autoConnect, client]);

  const value: ProviderValue = {
    client,
    state,
    error,
    connect: async () => {
      try {
        setError(null);
        await client.connect();
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to connect"));
        throw err;
      }
    },
    disconnect: async (reason?: string) => {
      try {
        setError(null);
        await client.disconnect(reason);
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to disconnect"));
        throw err;
      }
    },
    destroy: async () => {
      try {
        setError(null);
        await client.destroy();
      } catch (err) {
        setError(err instanceof Error ? err : new Error("Failed to destroy client"));
        throw err;
      }
    },
  };

  return <CachePuppyContext.Provider value={value}>{children}</CachePuppyContext.Provider>;
}

export function useCachePuppyContext(): ProviderValue {
  const value = useContext(CachePuppyContext);
  if (!value) {
    throw new Error("CachePuppyProvider is required");
  }
  return value;
}
