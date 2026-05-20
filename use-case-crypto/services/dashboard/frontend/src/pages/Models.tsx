import React, { useState } from "react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { Skeleton } from "../components/ui/skeleton";
import { useModels, useDeployModel } from "../hooks/queries";
import { formatDate } from "../utils/format";
import { useAuth } from "../context/AuthContext";
import { cn } from "../lib/utils";

export const Models: React.FC = () => {
  const { hasRole } = useAuth();
  const [selectedModel, setSelectedModel] = useState<any>(null);

  const { data: modelsRes, isLoading: loading } = useModels();
  const deployMutation = useDeployModel();

  const models = modelsRes?.data || [];
  const canDeploy = hasRole(["ml_engineer"]);

  const handleDeploy = async (modelName: string, version: string) => {
    try {
      await deployMutation.mutateAsync({
        modelName,
        version,
        stage: "Production",
      });
      alert(`Model ${modelName} v${version} deployed to Production`);
    } catch {
      alert("Failed to deploy model");
    }
  };

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Model Management</h1>
        <p className="text-gray-500 mt-1">View and manage ML models</p>
      </div>

      {loading ? (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="space-y-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-28 rounded-lg" />
            ))}
          </div>
          <div className="lg:col-span-2">
            <Skeleton className="h-96 rounded-xl" />
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Model List */}
          <div className="lg:col-span-1 space-y-4">
            <h2 className="text-lg font-semibold text-gray-900">
              Registered Models
            </h2>
            {models.map((model: any) => (
              <Card
                key={model.name}
                onClick={() => setSelectedModel(model)}
                className={cn(
                  "cursor-pointer transition-colors",
                  selectedModel?.name === model.name
                    ? "border-primary-500 ring-2 ring-primary-200"
                    : "hover:border-gray-300",
                )}
              >
                <CardContent className="p-4">
                  <h3 className="font-medium text-gray-900">{model.name}</h3>
                  <p className="text-sm text-muted-foreground mt-1">
                    {model.description}
                  </p>
                  <div className="flex items-center gap-2 mt-2">
                    <Badge className="bg-blue-100 text-blue-800 border-transparent">
                      Latest: v{model.latest_version}
                    </Badge>
                    {model.stages?.Production && (
                      <Badge className="bg-green-100 text-green-800 border-transparent">
                        Prod: v{model.stages.Production}
                      </Badge>
                    )}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Model Details */}
          <div className="lg:col-span-2">
            {selectedModel ? (
              <Card>
                <CardHeader>
                  <CardTitle>{selectedModel.name}</CardTitle>
                  <p className="text-muted-foreground">
                    {selectedModel.description}
                  </p>
                </CardHeader>
                <CardContent>
                  <h3 className="text-lg font-medium text-gray-900 mb-4">
                    Versions
                  </h3>
                  <div className="space-y-4">
                    {[
                      {
                        version: selectedModel.latest_version,
                        stage: "Staging",
                        created: new Date().toISOString(),
                      },
                      {
                        version: String(
                          Number(selectedModel.latest_version) - 1,
                        ),
                        stage: "Production",
                        created: new Date(
                          Date.now() - 86400000 * 7,
                        ).toISOString(),
                      },
                    ].map((v) => (
                      <div
                        key={v.version}
                        className="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
                      >
                        <div>
                          <span className="font-medium text-gray-900">
                            Version {v.version}
                          </span>
                          <Badge
                            className={cn(
                              "ml-2",
                              v.stage === "Production"
                                ? "bg-green-100 text-green-800 border-transparent"
                                : "bg-yellow-100 text-yellow-800 border-transparent",
                            )}
                          >
                            {v.stage}
                          </Badge>
                          <p className="text-sm text-muted-foreground mt-1">
                            Created: {formatDate(v.created)}
                          </p>
                        </div>
                        {canDeploy && v.stage !== "Production" && (
                          <Button
                            onClick={() =>
                              handleDeploy(selectedModel.name, v.version)
                            }
                            disabled={deployMutation.isPending}
                            size="sm"
                          >
                            {deployMutation.isPending
                              ? "Deploying..."
                              : "Deploy to Production"}
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            ) : (
              <div className="flex items-center justify-center h-64 bg-gray-50 rounded-xl border border-gray-200">
                <p className="text-muted-foreground">
                  Select a model to view details
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
