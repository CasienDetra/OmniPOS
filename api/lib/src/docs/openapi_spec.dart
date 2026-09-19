/// OpenAPI 3.0.3 document for the POS API, rendered at /swagger.
/// Kept as a JSON string so it can be served verbatim.
const openApiSpecJson = r'''
{
  "openapi": "3.0.3",
  "info": {
    "title": "POS API",
    "version": "1.0.0",
    "description": "Point-of-sale backend (Dart Frog + MongoDB). All responses use the envelope {\"success\": true, \"status_code\": n, \"data\": ...} or {\"success\": false, \"error\": \"...\"}. Authenticate via POST /api/account/auth/login, then send the returned token as \"Authorization: Bearer <token>\". Role 1 = Admin (guards /api/admin/*), role 2 = Cashier (guards /api/cashier/*)."
  },
  "servers": [
    {
      "url": "/",
      "description": "This server"
    }
  ],
  "tags": [
    {
      "name": "Health"
    },
    {
      "name": "Auth"
    },
    {
      "name": "Profile"
    },
    {
      "name": "Cashier"
    },
    {
      "name": "Admin / Products"
    },
    {
      "name": "Admin / Types"
    },
    {
      "name": "Admin / Sales"
    },
    {
      "name": "Admin / Users"
    },
    {
      "name": "Admin / Dashboard"
    },
    {
      "name": "Testing"
    }
  ],
  "security": [
    {
      "bearerAuth": []
    }
  ],
  "paths": {
    "/": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "Service health",
        "responses": {
          "200": {
            "description": "Service is up",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "object",
                          "properties": {
                            "service": {
                              "type": "string"
                            },
                            "status": {
                              "type": "string"
                            },
                            "time": {
                              "type": "string"
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/account/auth/login": {
      "post": {
        "tags": [
          "Auth"
        ],
        "security": [],
        "summary": "Login with username and password",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/LoginRequest"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "JWT returned",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/TokenResponse"
                        },
                        "message": {
                          "type": "string"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "401": {
            "$ref": "#/components/responses/Unauthorized"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/account/auth/switch": {
      "post": {
        "tags": [
          "Auth"
        ],
        "summary": "Switch active role, returns a new token",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "role_id"
                ],
                "properties": {
                  "role_id": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ],
                    "example": 2
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "New token for the selected role",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/TokenResponse"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          }
        }
      }
    },
    "/api/account/profile": {
      "get": {
        "tags": [
          "Profile"
        ],
        "summary": "Current user profile",
        "responses": {
          "200": {
            "description": "Profile",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/account/profile/update": {
      "put": {
        "tags": [
          "Profile"
        ],
        "summary": "Update own profile",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string"
                  },
                  "avatar": {
                    "type": "string",
                    "description": "base64 image; forwarded to the file service"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated profile",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/account/profile/update-password": {
      "put": {
        "tags": [
          "Profile"
        ],
        "summary": "Change own password",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "old_password",
                  "new_password"
                ],
                "properties": {
                  "old_password": {
                    "type": "string"
                  },
                  "new_password": {
                    "type": "string"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          }
        }
      }
    },
    "/api/account/profile/logs": {
      "get": {
        "tags": [
          "Profile"
        ],
        "summary": "Own login history (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          }
        ],
        "responses": {
          "200": {
            "description": "Login logs",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/UserLog"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/cashier/ordering/products": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "Ordering screen: product types with nested active products",
        "responses": {
          "200": {
            "description": "Types with products",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "allOf": [
                              {
                                "$ref": "#/components/schemas/ProductType"
                              },
                              {
                                "type": "object",
                                "properties": {
                                  "products": {
                                    "type": "array",
                                    "items": {
                                      "$ref": "#/components/schemas/Product"
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/cashier/ordering/order": {
      "post": {
        "tags": [
          "Cashier"
        ],
        "summary": "Checkout: create an order from a cart",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "cart"
                ],
                "properties": {
                  "cart": {
                    "description": "Mapping of product id to quantity, either a JSON string or an object",
                    "oneOf": [
                      {
                        "type": "string",
                        "example": "{\"64f1a0000000000000000001\": 2}"
                      },
                      {
                        "type": "object",
                        "additionalProperties": {
                          "type": "integer"
                        },
                        "example": {
                          "64f1a0000000000000000001": 2
                        }
                      }
                    ]
                  },
                  "platform": {
                    "type": "string",
                    "default": "Web"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Order placed; receipt number generated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        },
                        "message": {
                          "type": "string"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/cashier/sales": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "Own sales history (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "$ref": "#/components/parameters/Platform"
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Orders",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Order"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/cashier/sales/{id}": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "View own order detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Order",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Cashier"
        ],
        "summary": "Delete own order",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/products": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Product list (paginated, filterable)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "name": "type",
            "in": "query",
            "description": "Product type id",
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "creator",
            "in": "query",
            "description": "Creator user id",
            "schema": {
              "type": "string"
            }
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Products",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Product"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Create product",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/ProductInput"
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/admin/products/{id}": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Product detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Product",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Update product (all fields optional)",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/ProductInput"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Delete product",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/products/setup-data": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Dropdown data for the product form (types, creators)",
        "responses": {
          "200": {
            "description": "Setup data",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/admin/types": {
      "get": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Product type list (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          }
        ],
        "responses": {
          "200": {
            "description": "Types",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/ProductType"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Create product type",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name"
                ],
                "properties": {
                  "name": {
                    "type": "string",
                    "example": "Dessert"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/ProductType"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/admin/types/{id}": {
      "get": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Product type detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Type",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/ProductType"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Rename product type",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name"
                ],
                "properties": {
                  "name": {
                    "type": "string"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Delete product type",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/sales": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "All sales (paginated, filterable)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "name": "user",
            "in": "query",
            "description": "Cashier user id",
            "schema": {
              "type": "string"
            }
          },
          {
            "$ref": "#/components/parameters/Platform"
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Orders",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Order"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/admin/sales/{id}": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Order detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Order",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Delete order",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/sales/setup-data": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Dropdown data for the sales filter (cashiers)",
        "responses": {
          "200": {
            "description": "Setup data",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/admin/users": {
      "get": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "User list (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          }
        ],
        "responses": {
          "200": {
            "description": "Users",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/User"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Create user",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name",
                  "phone",
                  "email",
                  "password",
                  "roles"
                ],
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string",
                    "format": "email"
                  },
                  "password": {
                    "type": "string",
                    "format": "password"
                  },
                  "roles": {
                    "type": "array",
                    "items": {
                      "type": "integer",
                      "enum": [
                        1,
                        2
                      ]
                    },
                    "example": [
                      2
                    ]
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/admin/users/{id}": {
      "get": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "User detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "User",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Update user (name / phone / email / roles)",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string"
                  },
                  "roles": {
                    "type": "array",
                    "items": {
                      "type": "integer",
                      "enum": [
                        1,
                        2
                      ]
                    }
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Delete user",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/users/{id}/status": {
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Enable or disable a user",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "is_active"
                ],
                "properties": {
                  "is_active": {
                    "type": "boolean"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated user",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/users/{id}/password": {
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Reset a user's password",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "password"
                ],
                "properties": {
                  "password": {
                    "type": "string",
                    "format": "password"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/admin/dashboard": {
      "get": {
        "tags": [
          "Admin / Dashboard"
        ],
        "summary": "Dashboard aggregates (today's orders, revenue, top products)",
        "responses": {
          "200": {
            "description": "Dashboard payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/testing/basic": {
      "get": {
        "tags": [
          "Testing"
        ],
        "security": [],
        "summary": "Unauthenticated echo endpoint",
        "responses": {
          "200": {
            "description": "Echo",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/testing/upload/file": {
      "post": {
        "tags": [
          "Testing"
        ],
        "security": [],
        "summary": "Proxy a base64 image to the file service",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "image"
                ],
                "properties": {
                  "image": {
                    "type": "string",
                    "description": "data-URL base64 image"
                  },
                  "folder": {
                    "type": "string",
                    "default": "test"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "File service response (contains uri)",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/openapi": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "This OpenAPI document (JSON)",
        "responses": {
          "200": {
            "description": "OpenAPI 3.0.3 spec",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT"
      }
    },
    "parameters": {
      "IdPath": {
        "name": "id",
        "in": "path",
        "required": true,
        "description": "Mongo ObjectId hex string",
        "schema": {
          "type": "string",
          "example": "64f1a0000000000000000001"
        }
      },
      "Page": {
        "name": "page",
        "in": "query",
        "schema": {
          "type": "integer",
          "default": 1,
          "minimum": 1
        }
      },
      "Limit": {
        "name": "limit",
        "in": "query",
        "schema": {
          "type": "integer",
          "default": 10,
          "minimum": 1,
          "maximum": 100
        }
      },
      "Key": {
        "name": "key",
        "in": "query",
        "description": "Case-insensitive search keyword",
        "schema": {
          "type": "string"
        }
      },
      "SortBy": {
        "name": "sort_by",
        "in": "query",
        "x-aliases": [
          "sort"
        ],
        "description": "Field to sort by",
        "schema": {
          "type": "string"
        }
      },
      "Order": {
        "name": "order",
        "in": "query",
        "schema": {
          "type": "string",
          "enum": [
            "ASC",
            "DESC"
          ],
          "default": "ASC"
        }
      },
      "Platform": {
        "name": "platform",
        "in": "query",
        "schema": {
          "type": "string",
          "example": "Web"
        }
      },
      "StartDate": {
        "name": "startDate",
        "in": "query",
        "description": "Date range start (DD-MM-YYYY)",
        "schema": {
          "type": "string"
        }
      },
      "EndDate": {
        "name": "endDate",
        "in": "query",
        "description": "Date range end (DD-MM-YYYY)",
        "schema": {
          "type": "string"
        }
      }
    },
    "responses": {
      "BadRequest": {
        "description": "Bad request",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Unauthorized": {
        "description": "Missing or invalid token / bad credentials",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Forbidden": {
        "description": "Wrong role for this route",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "NotFound": {
        "description": "Entity not found",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Conflict": {
        "description": "Duplicate value (unique constraint)",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "InvalidEntity": {
        "description": "Validation failed",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ValidationErrorEnvelope"
            }
          }
        }
      },
      "SuccessNoData": {
        "description": "Success with no payload",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/SuccessEnvelope"
            }
          }
        }
      }
    },
    "schemas": {
      "SuccessEnvelope": {
        "type": "object",
        "required": [
          "success",
          "status_code"
        ],
        "properties": {
          "success": {
            "type": "boolean",
            "example": true
          },
          "status_code": {
            "type": "integer",
            "example": 200
          },
          "data": {
            "nullable": true
          },
          "message": {
            "type": "string"
          }
        }
      },
      "ErrorEnvelope": {
        "type": "object",
        "required": [
          "success",
          "status_code",
          "error"
        ],
        "properties": {
          "success": {
            "type": "boolean",
            "example": false
          },
          "status_code": {
            "type": "integer",
            "example": 401
          },
          "error": {
            "type": "string",
            "example": "Token not provided"
          },
          "timestamp": {
            "type": "string",
            "example": "19-09-2026 03:45:12 PM"
          },
          "path": {
            "type": "string",
            "example": "/api/admin/products"
          }
        }
      },
      "ValidationErrorEnvelope": {
        "allOf": [
          {
            "$ref": "#/components/schemas/ErrorEnvelope"
          },
          {
            "type": "object",
            "properties": {
              "errors": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "type": {
                      "type": "string",
                      "example": "field"
                    },
                    "message": {
                      "type": "string",
                      "example": "name is required"
                    }
                  }
                }
              }
            }
          }
        ]
      },
      "Paginated": {
        "type": "object",
        "properties": {
          "pagination": {
            "type": "object",
            "properties": {
              "page": {
                "type": "integer"
              },
              "limit": {
                "type": "integer"
              },
              "totalPage": {
                "type": "integer"
              },
              "total": {
                "type": "integer"
              }
            }
          }
        }
      },
      "LoginRequest": {
        "type": "object",
        "required": [
          "username",
          "password"
        ],
        "properties": {
          "username": {
            "type": "string",
            "example": "admin@pos.local"
          },
          "password": {
            "type": "string",
            "format": "password",
            "example": "admin123"
          },
          "platform": {
            "type": "string",
            "default": "Web"
          }
        }
      },
      "TokenResponse": {
        "type": "object",
        "properties": {
          "token": {
            "type": "string",
            "description": "JWT (HS256, 24h). Payload embeds the user and its roles; the default role is marked is_default."
          }
        }
      },
      "User": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "phone": {
            "type": "string"
          },
          "email": {
            "type": "string"
          },
          "avatar": {
            "type": "string",
            "nullable": true,
            "description": "Relative file path, e.g. api/file/<uuid>"
          },
          "is_active": {
            "type": "boolean"
          },
          "roles": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "role_id": {
                  "type": "integer",
                  "enum": [
                    1,
                    2
                  ]
                },
                "name": {
                  "type": "string",
                  "enum": [
                    "Admin",
                    "Cashier"
                  ]
                },
                "is_default": {
                  "type": "boolean"
                }
              }
            }
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "UserLog": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "user_id": {
            "type": "string"
          },
          "ip": {
            "type": "string"
          },
          "user_agent": {
            "type": "string"
          },
          "platform": {
            "type": "string"
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "ProductType": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "ProductInput": {
        "type": "object",
        "required": [
          "name",
          "code",
          "type",
          "unit_price"
        ],
        "properties": {
          "name": {
            "type": "string",
            "example": "Test Burger"
          },
          "code": {
            "type": "string",
            "example": "P0005",
            "description": "Unique product code"
          },
          "type": {
            "type": "string",
            "description": "Product type id"
          },
          "unit_price": {
            "type": "number",
            "minimum": 0,
            "example": 4.5
          },
          "image": {
            "type": "string",
            "nullable": true,
            "description": "data-URL base64 image; forwarded to the file service, stored as api/file/<uuid>"
          },
          "is_active": {
            "type": "boolean",
            "default": true
          }
        }
      },
      "Product": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "code": {
            "type": "string"
          },
          "type": {
            "type": "string",
            "description": "Product type id"
          },
          "type_name": {
            "type": "string",
            "nullable": true
          },
          "unit_price": {
            "type": "number"
          },
          "image": {
            "type": "string",
            "nullable": true
          },
          "is_active": {
            "type": "boolean"
          },
          "creator_id": {
            "type": "string"
          },
          "creator_name": {
            "type": "string",
            "nullable": true
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "OrderItem": {
        "type": "object",
        "properties": {
          "product_id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "qty": {
            "type": "integer"
          },
          "unit_price": {
            "type": "number",
            "description": "Price snapshotted at sale time"
          },
          "line_price": {
            "type": "number"
          }
        }
      },
      "Order": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "receipt_number": {
            "type": "string",
            "description": "Sequential 7-digit receipt number",
            "example": "1000001"
          },
          "cashier_id": {
            "type": "string"
          },
          "cashier_name": {
            "type": "string",
            "nullable": true
          },
          "platform": {
            "type": "string",
            "example": "Web"
          },
          "total_price": {
            "type": "number"
          },
          "items": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/OrderItem"
            }
          },
          "ordered_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      }
    }
  }
}
''';
