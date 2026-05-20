import React, { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { TrendingUp, AlertCircle } from "lucide-react";
import { useAuth } from "../context/AuthContext";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";

export const Login: React.FC = () => {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const { login } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setIsLoading(true);

    try {
      await login(username, password);
      navigate({ to: "/" });
    } catch (err: any) {
      setError(err.message || "Login failed");
    } finally {
      setIsLoading(false);
    }
  };

  // Demo users for development - credentials should be configured via environment
  const demoUsers = [
    { username: "data_engineer", role: "Data Engineer" },
    { username: "data_scientist", role: "Data Scientist" },
    { username: "ml_engineer", role: "ML Engineer" },
    { username: "business_user", role: "Business User" },
  ];

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4">
      <div className="max-w-md w-full space-y-8">
        <div className="text-center">
          <div className="flex justify-center">
            <TrendingUp className="h-12 w-12 text-primary-600" />
          </div>
          <h2 className="mt-6 text-3xl font-bold text-gray-900">
            ML Pipeline Dashboard
          </h2>
          <p className="mt-2 text-sm text-gray-600">Sign in to your account</p>
        </div>

        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          {error && (
            <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">
              <AlertCircle className="h-5 w-5" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-4">
            <div>
              <label
                htmlFor="username"
                className="block text-sm font-medium text-gray-700"
              >
                Username
              </label>
              <Input
                id="username"
                name="username"
                type="text"
                required
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="mt-1 h-12"
                placeholder="Enter username"
              />
            </div>

            <div>
              <label
                htmlFor="password"
                className="block text-sm font-medium text-gray-700"
              >
                Password
              </label>
              <Input
                id="password"
                name="password"
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 h-12"
                placeholder="Enter password"
              />
            </div>
          </div>

          <Button type="submit" disabled={isLoading} className="w-full h-12">
            {isLoading ? "Signing in..." : "Sign in"}
          </Button>
        </form>

        {/* Demo Users */}
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium text-gray-700">
              Available Roles:
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {demoUsers.map((user) => (
              <button
                key={user.username}
                type="button"
                onClick={() => {
                  setUsername(user.username);
                }}
                className="block w-full text-left px-3 py-2 text-sm bg-white rounded hover:bg-gray-50 border border-gray-200"
              >
                <span className="font-medium">{user.role}</span>
                <span className="text-gray-500 ml-2">({user.username})</span>
              </button>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  );
};
