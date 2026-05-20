import React from "react";
import { Link, useLocation, useNavigate } from "@tanstack/react-router";
import {
  LayoutDashboard,
  TrendingUp,
  Database,
  Box,
  Activity,
  LogOut,
  User,
} from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { getRoleLabel, getRoleColor } from "../utils/format";
import { Button } from "./ui/button";
import { cn } from "../lib/utils";

interface LayoutProps {
  children: React.ReactNode;
}

export const Layout: React.FC<LayoutProps> = ({ children }) => {
  const { user, logout, hasRole } = useAuth();
  const location = useLocation();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate({ to: "/login" });
  };

  const navItems = [
    {
      path: "/" as const,
      icon: LayoutDashboard,
      label: "Dashboard",
      roles: [
        "data_engineer",
        "data_scientist",
        "ml_engineer",
        "business_user",
      ],
    },
    {
      path: "/predictions" as const,
      icon: TrendingUp,
      label: "Predictions",
      roles: [
        "data_engineer",
        "data_scientist",
        "ml_engineer",
        "business_user",
      ],
    },
    {
      path: "/features" as const,
      icon: Database,
      label: "Features",
      roles: ["data_engineer", "data_scientist", "ml_engineer"],
    },
    {
      path: "/models" as const,
      icon: Box,
      label: "Models",
      roles: ["data_scientist", "ml_engineer"],
    },
    {
      path: "/monitoring" as const,
      icon: Activity,
      label: "Monitoring",
      roles: ["data_engineer", "ml_engineer"],
    },
  ];

  const filteredNavItems = navItems.filter((item) =>
    hasRole(item.roles as any[]),
  );

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Sidebar */}
      <aside className="fixed left-0 top-0 z-40 h-screen w-64 bg-white border-r border-gray-200">
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className="flex items-center gap-2 px-6 py-4 border-b border-gray-200">
            <TrendingUp className="h-8 w-8 text-primary-600" />
            <span className="text-xl font-bold text-gray-900">ML Pipeline</span>
          </div>

          {/* Navigation */}
          <nav className="flex-1 px-4 py-4 space-y-1">
            {filteredNavItems.map((item) => {
              const isActive = location.pathname === item.path;
              const Icon = item.icon;
              return (
                <Link
                  key={item.path}
                  to={item.path}
                  className={cn(
                    "flex items-center gap-3 px-4 py-3 rounded-lg transition-colors",
                    isActive
                      ? "bg-primary-50 text-primary-700"
                      : "text-gray-600 hover:bg-gray-100",
                  )}
                >
                  <Icon className="h-5 w-5" />
                  <span className="font-medium">{item.label}</span>
                </Link>
              );
            })}
          </nav>

          {/* User info */}
          <div className="p-4 border-t border-gray-200">
            <div className="flex items-center gap-3 px-4 py-3 bg-gray-50 rounded-lg">
              <div className="flex items-center justify-center h-10 w-10 rounded-full bg-primary-100 text-primary-700">
                <User className="h-5 w-5" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-900 truncate">
                  {user?.username}
                </p>
                <span
                  className={cn(
                    "inline-block px-2 py-0.5 text-xs font-medium rounded",
                    getRoleColor(user?.role || ""),
                  )}
                >
                  {getRoleLabel(user?.role || "")}
                </span>
              </div>
            </div>
            <Button
              variant="ghost"
              onClick={handleLogout}
              className="flex items-center gap-2 w-full px-4 py-3 mt-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors justify-start"
            >
              <LogOut className="h-5 w-5" />
              <span className="font-medium">Logout</span>
            </Button>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <main className="ml-64 p-8">{children}</main>
    </div>
  );
};
