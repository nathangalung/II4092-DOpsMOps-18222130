import {
  createRouter,
  createRootRouteWithContext,
  createRoute,
  redirect,
  Outlet,
} from "@tanstack/react-router";
import { Layout } from "./components/Layout";
import { Login } from "./pages/Login";
import { Dashboard } from "./pages/Dashboard";
import { Predictions } from "./pages/Predictions";
import { Features } from "./pages/Features";
import { Models } from "./pages/Models";
import { Monitoring } from "./pages/Monitoring";
import type { Role } from "./types";

// Context type passed to routes
interface RouterContext {
  auth: {
    isAuthenticated: boolean;
    isLoading: boolean;
    user: { role: Role } | null;
    hasRole: (roles: Role[]) => boolean;
  };
}

// Root route
const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: () => <Outlet />,
});

// Login route
const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/login",
  beforeLoad: ({ context }) => {
    if (context.auth.isAuthenticated) {
      throw redirect({ to: "/" });
    }
  },
  component: Login,
});

// Authenticated layout route (wraps all protected routes)
const authenticatedRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: "authenticated",
  beforeLoad: ({ context }) => {
    if (!context.auth.isAuthenticated) {
      throw redirect({ to: "/login" });
    }
  },
  component: () => (
    <Layout>
      <Outlet />
    </Layout>
  ),
});

// Dashboard route (index)
const dashboardRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/",
  component: Dashboard,
});

// Predictions route
const predictionsRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/predictions",
  component: Predictions,
});

// Features route (role restricted)
const featuresRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/features",
  beforeLoad: ({ context }) => {
    if (
      !context.auth.hasRole(["data_engineer", "data_scientist", "ml_engineer"])
    ) {
      throw redirect({ to: "/unauthorized" });
    }
  },
  component: Features,
});

// Models route (role restricted)
const modelsRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/models",
  beforeLoad: ({ context }) => {
    if (!context.auth.hasRole(["data_scientist", "ml_engineer"])) {
      throw redirect({ to: "/unauthorized" });
    }
  },
  component: Models,
});

// Monitoring route (role restricted)
const monitoringRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/monitoring",
  beforeLoad: ({ context }) => {
    if (!context.auth.hasRole(["data_engineer", "ml_engineer"])) {
      throw redirect({ to: "/unauthorized" });
    }
  },
  component: Monitoring,
});

// Unauthorized route
const unauthorizedRoute = createRoute({
  getParentRoute: () => authenticatedRoute,
  path: "/unauthorized",
  component: () => (
    <div className="flex items-center justify-center min-h-[60vh]">
      <div className="text-center">
        <h1 className="text-2xl font-bold text-gray-900">Unauthorized</h1>
        <p className="text-gray-500 mt-2">
          You don&apos;t have permission to access this page.
        </p>
      </div>
    </div>
  ),
});

// Route tree
const routeTree = rootRoute.addChildren([
  loginRoute,
  authenticatedRoute.addChildren([
    dashboardRoute,
    predictionsRoute,
    featuresRoute,
    modelsRoute,
    monitoringRoute,
    unauthorizedRoute,
  ]),
]);

// Create the router
export const router = createRouter({
  routeTree,
  context: {
    auth: undefined!,
  },
  defaultNotFoundComponent: () => (
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <h1 className="text-2xl font-bold text-gray-900">Page Not Found</h1>
        <p className="text-gray-500 mt-2">
          The page you are looking for does not exist.
        </p>
      </div>
    </div>
  ),
});

// Type augmentation for TanStack Router
declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
