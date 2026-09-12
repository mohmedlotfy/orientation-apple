# API Routes Documentation

This document contains all routes in the Orientation App Backend project, including request and response data structures.

**Base URL**: `/api/v1` (configurable via `PORT` environment variable, default: 5000)

---

## 1. App Controller

### GET `/`

**Description**: Returns a simple hello world message  
**Authentication**: None  
**Request**: None  
**Response**:

```typescript
string; // "Hello World!"
```

---

## 2. Auth Controller (`/auth`)

### POST `/auth/register`

**Description**: Register a new user (unverified). Sends a 4-digit OTP to the user's email for verification.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request Body** (`RegisterDto`):

```typescript
{
  username: string; // Required
  email: string; // Valid email address (required)
  phoneNumber?: string; // Valid phone number (optional)
  password: string; // 8-20 characters (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "Registration successful. Please check your email for verification code."
  email: string; // User's email address
}
```

**Note**: User CANNOT log in until their email is verified via OTP. OTP expires in 2 minutes.

---

### POST `/auth/verify-email`

**Description**: Verify email with 4-digit OTP.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request Body** (`VerifyEmailDto`):

```typescript
{
  email: string; // Valid email address (required)
  otp: string; // 4-digit OTP string (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "Email verified successfully"
}
```

**Error Responses**:

- `400 Bad Request`: "User not found"
- `400 Bad Request`: "Email already verified"
- `400 Bad Request`: "Invalid verification code" / "Verification code has expired"

---

### POST `/auth/resend-verification`

**Description**: Resend verification OTP to email  
**Authentication**: None (Public)  
**Rate Limit**: 3 requests / 60 seconds  
**Request Body** (`ResendVerificationDto`):

```typescript
{
  email: string; // Valid email address (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "Verification code sent to your email"
}
```

---

### POST `/auth/login`

**Description**: Login with email and password for verified users. Issues access & refresh tokens and sets HTTP-only cookies.  
**Authentication**: None (Public)  
**Rate Limit**: 10 requests / 60 seconds  
**Request Body** (`LoginDto`):

```typescript
{
  email: string; // Valid email address (required)
  password: string; // 8-20 characters (required)
}
```

**Response**:

```typescript
{
  id: string; // User MongoDB ObjectId
  accessToken: string; // JWT access token
  refreshToken: string; // JWT refresh token
}
```

**Cookies Set**:
- `accessToken`: HTTP-only cookie (Max age: 5 minutes)
- `refreshToken`: HTTP-only cookie (Max age: 7 days)

**Error Responses**:

- `401 Unauthorized`: "Invalid credentials"
- `401 Unauthorized`: "This account was registered using Google. Please log in with Google or reset your password to create one."

---

### POST `/auth/refresh`

**Description**: Refresh tokens using refresh token rotation.  
**Authentication**: Requires valid Refresh Token (passed via HTTP-only cookie `refreshToken` or Bearer header)  
**Rate Limit**: 10 requests / 60 seconds  
**Request**: None (reads token from cookie or Authorization header)  
**Response**:

```typescript
{
  id: string; // User MongoDB ObjectId
  accessToken: string; // New short-lived access token
  refreshToken: string; // New rotated refresh token
}
```

**Cookies Updated**:
- `accessToken`: Updated HTTP-only cookie
- `refreshToken`: Updated HTTP-only cookie

---

### POST `/auth/signout`

**Description**: Sign out the user, clear auth cookies, and invalidate stored refresh token in the database.  
**Authentication**: Required (`JwtAuthGuard` - Bearer token or `accessToken` cookie)  
**Rate Limit**: 5 requests / 60 seconds  
**Request**: None  
**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "User signed out successfully"
}
```

---

### POST `/auth/forgot-password`

**Description**: Request password reset. Sends a 4-digit OTP to the user's email.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request Body** (`ForgotPasswordDto`):

```typescript
{
  email: string; // Valid email address (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "Password reset code sent to your email"
}
```

---

### POST `/auth/verify-reset-otp`

**Description**: Step 2 of password reset — Verify the OTP received via email before setting a new password.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request Body** (`VerifyEmailDto`):

```typescript
{
  email: string; // Valid email address (required)
  otp: string; // 4-digit OTP string (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "OTP verified successfully. You can now reset your password."
}
```

---

### POST `/auth/reset-password`

**Description**: Step 3 of password reset — Set a new password after OTP has been verified in Step 2.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request Body** (`ResetPasswordDto`):

```typescript
{
  email: string; // Valid email address (required)
  newPassword: string; // New password (8-20 characters) (required)
}
```

**Response**:

```typescript
{
  success: boolean; // true
  message: string; // "Password has been reset successfully"
}
```

**Note**: All active refresh tokens are invalidated upon password reset to enforce re-authentication.

---

### GET `/auth/google/login`

**Description**: Initiates Web Google OAuth 2.0 login flow. Redirects user's browser to Google's consent screen.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request**: None  
**Response**: `302 Redirect` to `accounts.google.com`

---

### GET `/auth/google/callback`

**Description**: Web Google OAuth 2.0 callback endpoint. Google redirects here with authorization code. Generates JWT tokens, sets HTTP-only auth cookies, and redirects the browser to the frontend.  
**Authentication**: None (Public - handled by `GoogleAuthGuard`)  
**Rate Limit**: 5 requests / 60 seconds  
**Response**: `302 Redirect` to `${FRONTEND_URL}?token=${accessToken}`

---

### POST `/auth/google/mobile`

**Description**: Native Mobile 1-Tap Google Sign-In endpoint (for Flutter, React Native, iOS Swift, Android Kotlin). Verifies the Google `idToken` cryptographically and returns user authentication tokens.  
**Authentication**: None (Public)  
**Rate Limit**: 10 requests / 60 seconds  
**Request Body** (`GoogleMobileDto`):

```typescript
{
  idToken: string; // Google ID token obtained from native mobile Google Sign-In SDK (required)
}
```

**Response**:

```typescript
{
  id: string; // User MongoDB ObjectId
  accessToken: string; // JWT access token
  refreshToken: string; // JWT refresh token
}
```

**Cookies Set**:
- `accessToken`: HTTP-only cookie
- `refreshToken`: HTTP-only cookie

---

### GET `/auth/apple/login`

**Description**: Initiates Web Apple OAuth login flow. Redirects user's browser to Apple's authorization dialog.  
**Authentication**: None (Public)  
**Rate Limit**: 5 requests / 60 seconds  
**Request**: None  
**Response**: `302 Redirect` to `appleid.apple.com`

---

### POST `/auth/apple/callback`

**Description**: Web Apple OAuth callback endpoint (Apple uses HTTP `form_post`). Generates JWT tokens, sets HTTP-only cookies, and redirects the browser to the frontend.  
**Authentication**: None (Public - handled by `AppleAuthGuard`)  
**Rate Limit**: 5 requests / 60 seconds  
**Response**: `302 Redirect` to `${FRONTEND_URL}?token=${accessToken}`

---

### POST `/auth/apple/mobile`

**Description**: Native Mobile 1-Tap Apple Sign-In endpoint (for iOS Swift, Flutter `sign_in_with_apple`, React Native Apple Authentication). Verifies the Apple `identityToken` cryptographically and returns user tokens.  
**Authentication**: None (Public)  
**Rate Limit**: 10 requests / 60 seconds  
**Request Body** (`AppleMobileDto`):

```typescript
{
  identityToken: string; // Apple identityToken from native Apple SDK (required)
  firstName?: string; // Optional (provided on first login)
  lastName?: string; // Optional (provided on first login)
  email?: string; // Optional (provided on first login)
  name?: {
    firstName?: string;
    lastName?: string;
  };
}
```

**Response**:

```typescript
{
  id: string; // User MongoDB ObjectId
  accessToken: string; // JWT access token
  refreshToken: string; // JWT refresh token
}
```

**Cookies Set**:
- `accessToken`: HTTP-only cookie
- `refreshToken`: HTTP-only cookie

---

## 3. Users Controller (`/users`)

### POST `/users`

**Description**: Create a new admin user
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `SUPERADMIN`
**Request Body** (`CreateUserDto`):

```typescript
{
  username: string; // Required
  email: string; // Valid email address (required)
  phoneNumber: string; // Valid phone number (required)
  password: string; // 8-20 characters, must contain: uppercase, lowercase, number, special char (required)
}
````

**Response**: User object (from service)

---

### GET `/users`

**Description**: Get all users  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Request**: None  
**Response**: Array of user objects

---

### GET `/users/saved-projects`

**Description**: Get projects saved by the current user
**Authentication**: Required (`AuthGuard`)
**Required Role**: Any authenticated user
**Request**: None
**Note**: User ID is extracted from JWT token (`req.user.sub`)
**Response**: 

```typescript
{
  message: string; // "Saved projects retrieved successfully"
  savedProjects: Array<{
    _id: string;
    title: string;
    projectThumbnailUrl: string;
  }>;
}
```

---

### GET `/users/saved-reels`

**Description**: Get reels saved by the current user
**Authentication**: Required (`AuthGuard`)
**Required Role**: Any authenticated user
**Request**: None
**Note**: User ID is extracted from JWT token (`req.user.sub`)
**Response**: 

```typescript
{
  message: string; // "Saved reels retrieved successfully"
  savedReels: Array<{
    _id: string;
    title: string;
    reelThumbnailUrl: string;
  }>;
}
```

---

### GET `/users/profile`

**Description**: Get current user profile
**Authentication**: Required (`AuthGuard`)
**Required Role**: Any authenticated user
**Request**: None
**Response**: User object

---

### PATCH `/users/profile`

**Description**: Update current user profile
**Authentication**: Required (`AuthGuard`)
**Required Role**: Any authenticated user
**Request Body** (`UpdateUserDto` - all fields optional):

```typescript
{
  username?: string;
  email?: string;
  phoneNumber?: string;
  password?: string;  // 8-20 characters with complexity requirements
}
```

**Response**: Updated user object

---

### GET `/users/:id`

**Description**: Get a user by ID  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: User object

---

### PATCH `/users/:id`

**Description**: Update a user (Admin)
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `SUPERADMIN` or `ADMIN`
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateUserDto` - all fields optional):

```typescript
{
  username?: string;
  email?: string;
  phoneNumber?: string;
  password?: string;  // 8-20 characters with complexity requirements
}
```

**Response**: Updated user object

---

### DELETE `/users/:id`

**Description**: Delete a user  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Deletion confirmation

---

## 4. Projects Controller (`/projects`)

### POST `/projects`

**Description**: Create a new project  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateProjectDto`):

```typescript
{
  title: string;                    // Required
  developer: string;                // MongoDB ObjectId (required)
  location: string;                 // Required
  status?: string;                  // 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED'
  script: string;                   // Required
  episodes?: any;                   // Optional
  reels?: any;                      // Optional
  inventory?: string;               // MongoDB ObjectId (optional)
  pdf?: string[];                   // Array of MongoDB ObjectIds (optional)
  whatsappNumber?: string;          // Valid phone number (optional)
  featured?: boolean;               // Optional
  mapsLocation?: string;            // Optional
  published?: boolean;              // Optional
}
```

**Files**:

- `logo`: File (max 1GB, single file, optional)
- `heroVideo`: File (max 1GB, single file, required)
- `projectThumbnail`: File (max 1GB, single file, required)

**Response**:

```typescript
{
  message: string; // "Project created successfully"
  project: string; // Created Project MongoDB ObjectId
}
```

---

### POST `/projects/upcomming`

**Description**: Create a new upcoming project (status defaulted to `PLANNING`)  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateUpcommingProjectDto`):

```typescript
{
  title: string;                    // Required
  developer: string;                // MongoDB ObjectId (required)
  location: string;                 // Required
}
```

**Files**:

- `projectThumbnail`: File (max 1GB, single file, required)

**Response**:

```typescript
{
  message: string; // "Upcoming project created successfully"
  project: string; // Created Project MongoDB ObjectId
}
```

---

### GET `/projects`

**Description**: List/search projects with optional filters, sorting, and pagination. Main listing endpoint.  
**Authentication**: None  
**Query Parameters** (`QueryProjectDto`):

```typescript
{
  developerId?: string;  // MongoDB ObjectId (optional) - filter by developer
  location?: string;     // Optional - filter by location
  status?: string;       // 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED'
  title?: string;       // Optional - filter by title
  limit?: number;       // 1-100 (optional) - page size
  page?: number;        // min 1 (optional) - page number (used with limit)
  sortBy?: string;      // 'newest' | other field name (optional)
}
```

**Response**: Array of project objects:

```typescript
Array<{
  _id: string;
  slug: string;
  title: string;
  location: string;
  developer: string;
  status: 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED';
  createdAt: Date;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/:id`

**Description**: Get a project by ID. Returns project with populated `developer`, `episodes`, `reels`, `inventory`, and `pdf` fields. Automatically increments view count and recalculates trending score.  
**Authentication**: None  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Project object with populated references:

```typescript
{
  _id: string;
  title: string;
  slug: string;
  logoUrl?: string;
  location: string;
  status: 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED';
  developer: { _id: string; name: string; logoUrl?: string };
  script: string;
  episodes: Array<{ _id: string; title: string; thumbnail?: string; episodeUrl: string; duration?: string; episodeOrder: string }>;
  reels: Array<{ _id: string; videoUrl: string; thumbnail?: string; title: string }>;
  inventory?: { _id: string; title: string; inventoryUrl: string };
  pdf: Array<{ _id: string; title: string; pdfUrl: string }>;
  projectThumbnailUrl: string;
  heroVideoUrl: string;
  whatsappNumber?: string;
  trendingScore: number;
  saveCount: number;
  viewCount: number;
  published: boolean;
  createdAt: Date;
  updatedAt: Date;
}
```

---

### GET `/projects/featured?limit=10`

**Description**: Get featured projects  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  limit?: string;  // Converted to number, default: 10
}
```

**Response**: Array of featured project objects:

```typescript
Array<{
  _id: string;
  title: string;
  location: string;
  status: string;
  developer: string;
  slug: string;
  ad_url: string;
  adUrl: string;
  heroVideoUrl: string;
}>;
```

---

### GET `/projects/latest?limit=10`

**Description**: Get latest projects (excludes upcoming projects with `status: 'PLANNING'`; default limit = 10)  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  limit?: string;  // Converted to number, default: 10
}
```

**Response**: Array of latest project objects:

```typescript
Array<{
  _id: string;
  title: string;
  slug: string;
  status: 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED';
  location: string;
  developer: string;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/upcoming?limit=10`

**Description**: Get upcoming projects (`status: 'PLANNING'`; default limit = 10)  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  limit?: string;  // Converted to number, default: 10
}
```

**Response**: Array of upcoming project objects:

```typescript
Array<{
  _id: string;
  title: string;
  slug: string;
  status: 'PLANNING';
  location: string;
  developer: string;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/top10?limit=10`

**Description**: Get top 10 / trending projects sorted by `trendingScore` descending with rank  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  limit?: string;  // Converted to number, default: 10
}
```

**Response**: Array of top trending project objects with rank:

```typescript
Array<{
  rank: number;
  _id: string;
  slug: string;
  title: string;
  location: string;
  status: string;
  developer: string;
  published: boolean;
  projectThumbnailUrl: string;
  trendingScore: number;
  saveCount: number;
  viewCount: number;
  createdAt: Date;
}>;
```

---

### GET `/projects/location?location=North%20Coast&limit=10`

**Description**: Search projects by location using case-insensitive matching  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  location: string; // Required - filter by location
  limit?: string;   // Converted to number, default: 10
}
```

**Response**: Array of project objects filtered by location:

```typescript
Array<{
  _id: string;
  slug: string;
  title: string;
  status: string;
  location: string;
  developer: string;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/developer?developer=60d0fe4f5311236168a109ca`

**Description**: Get projects by developer ID  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  developer: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Array of project objects belonging to the developer:

```typescript
Array<{
  _id: string;
  slug: string;
  title: string;
  location: string;
  developer: string;
  status: string;
  createdAt: Date;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/status?status=CONSTRUCTION`

**Description**: Get projects by specific status  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  status: string; // 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED'
}
```

**Response**: Array of project objects:

```typescript
Array<{
  _id: string;
  slug: string;
  title: string;
  location: string;
  developer: string;
  published: boolean;
  projectThumbnailUrl: string;
}>;
```

---

### GET `/projects/title?title=Direction%20White`

**Description**: Get project by exact title match (case-insensitive)  
**Authentication**: None  
**Query Parameters**:

```typescript
{
  title: string; // Required
}
```

**Response**: Matching project object:

```typescript
{
  _id: string;
  slug: string;
  title: string;
  location: string;
  developer: string;
  status: string;
  createdAt: Date;
  published: boolean;
  projectThumbnailUrl: string;
}
```

---

### PATCH `/projects/:id`

**Description**: Update project details and replace S3 media files if provided  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Type**: `multipart/form-data`  
**Request Body** (`UpdateProjectDto` - all fields optional):

```typescript
{
  title?: string;
  developer?: string;                // MongoDB ObjectId
  location?: string;
  status?: 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED';
  script?: string;
  featured?: boolean;
  mapsLocation?: string;
  whatsappNumber?: string;
  inventory?: string;                // MongoDB ObjectId
  pdf?: string[];                    // Array of MongoDB ObjectIds
  published?: boolean;
}
```

**Files** (optional - if provided, replaces the old file in S3):

- `logo`: File (max 1GB, single file, optional) - replaces old logo
- `heroVideo`: File (max 1GB, single file, optional) - replaces old hero video
- `projectThumbnail`: File (max 1GB, single file, optional) - replaces old thumbnail

**Response**:

```typescript
{
  message: string; // "Project updated successfully"
  project: Project; // Updated project object (internal fields like __v, deletedAt, stats excluded)
}
```

---

### DELETE `/projects/:id`

**Description**: Soft delete a project and permanently remove all associated episodes, reels, inventory, and PDFs from S3 and database  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Project and all associated data deleted successfully"
  project: Project;
}
```

---

### PATCH `/projects/:id/save-project`

**Description**: Save a project to user's bookmarks, increment save count, and recalculate trending score  
**Authentication**: Required (`JwtAuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Project saved successfully" | "Project already saved"
}
```

---

### PATCH `/projects/:id/unsave-project`

**Description**: Remove a project from user's bookmarks, decrement save count, and recalculate trending score  
**Authentication**: Required (`JwtAuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Project unsaved successfully"
}
```

---

### PUT `/projects/:id/publish`

**Description**: Publish a project  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Project published successfully" | "Project is already published"
  project: Project; // Updated project object with published=true and publishedAt timestamp
}
```

---

### PUT `/projects/:id/unpublish`

**Description**: Unpublish a project  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `SUPERADMIN` or `ADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Project unpublished successfully" | "Project is already unpublished"
  project: Project; // Updated project object with published=false and publishedAt=null
}
```

---

## 5. Developer Controller (`/developer`)

### GET `/developer`

**Description**: Get all developers  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request**: None  
**Response**: Array of developer objects

---

### GET `/developer/me/profile`

**Description**: Get current developer profile
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `DEVELOPER`
**Request**: None
**Response**: Developer object

---

### GET `/developer/me/projects`

**Description**: Get current developer's projects
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `DEVELOPER`
**Request**: None
**Response**: Array of project objects

---

### PATCH `/developer/me/profile`

**Description**: Update current developer profile
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `DEVELOPER`
**Request Body** (`UpdateDeveloperDto`): Same as `PATCH /developer/:id`
**Response**: Updated developer object

---

### POST `/developer/create-account`

**Description**: Create a user account for an existing developer entity
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `ADMIN` or `SUPERADMIN`
**Request Body** (`CreateDeveloperAccountDto`):

```typescript
{
  developerId: string; // Valid MongoDB ObjectId (required)
  password: string; // 8-20 chars, complex (required)
}
```

**Response**: User object

---

### POST `/developer/:developerId/link-user/:userId`

**Description**: Link an existing user to a developer
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `ADMIN` or `SUPERADMIN`
**Response**: Updated developer object

---

### DELETE `/developer/:developerId/unlink-user`

**Description**: Unlink user from a developer
**Authentication**: Required (`AuthGuard`, `RolesGuard`)
**Required Role**: `ADMIN` or `SUPERADMIN`
**Response**: Updated developer object

---

### GET `/developer/:id`

**Description**: Get a developer by ID  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Developer object

---

### POST `/developer`

**Description**: Create a new developer  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateDeveloperDto`):

```typescript
{
  name: string;              // Required
  email?: string;            // Valid email address (optional)
  phone?: string;            // Optional
  socialMediaLink?: string;  // Optional
  location: string;          // Required
}
```

**Files**:

- `logo`: File (single file, optional)

**Response**: Developer object

---

### POST `/developer/join-developer`

**Description**: Submit a "join developer" request. The backend sends the submitted data to `ADMIN_NOTIFICATION_EMAIL` via SMTP.  
**Authentication**: Required (`JwtAuthGuard`)  
**Request Body** (`JoinDeveloperDto`):

```typescript
{
  name: string;            // Required
  address: string;         // Required
  phoneNumber: string;     // Required
  numberOfProjects: number; // Required
  socialmediaLink: string; // Required (URL)
  notes?: string;          // Optional
}
```

**Response**:

```typescript
{
  message: string; // "Join developer request sent successfully"
}
```

**Note**: Configure `ADMIN_NOTIFICATION_EMAIL` in `.env` to receive requests.

---

### PATCH `/developer/:id`

**Description**: Update a developer  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateDeveloperDto` - all fields optional):

```typescript
{
  name?: string;
  email?: string;
  phone?: string;
  socialMediaLink?: string;
  location?: string;
}
```

**Response**: Updated developer object

---

### PATCH `/developer/:id/project`

**Description**: Update developer's project script  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `DEVELOPER`, `ADMIN`, or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateDeveloperScriptDto`):

```typescript
{
  script: string; // Required
}
```

**Response**: Updated developer object

---

### DELETE `/developer/:id`

**Description**: Delete a developer  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Deletion confirmation

---

## 6. Episode Controller (`/episode`)

### POST `/episode`

**Description**: Upload/create a new episode  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateEpisodeDto`):

```typescript
{
  projectId: string;      // MongoDB ObjectId (required)
  title: string;          // Required
  thumbnail?: string;     // Optional
  episodeOrder: string;   // Required
  duration: string;       // Required
}
```

**Files**:

- `file`: Video file (max 5GB, required)

**Note**: User ID is extracted from JWT token (`req.user.sub`)

**Response**:

```typescript
{
  message: string; // "Episode uploaded successfully"
  episode: Episode; // Created episode object
}
```

---

### GET `/episode`

**Description**: Get all episodes  
**Authentication**: None  
**Request**: None  
**Response**: Array of episode objects

---

### GET `/episode/:id`

**Description**: Get an episode by ID  
**Authentication**: None  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Episode object

---

### PATCH `/episode/:id`

**Description**: Update an episode (with optional file replacement)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateEpisodeDto` - all fields optional):

```typescript
{
  title?: string;
  episodeOrder?: number;   // Min: 1
  duration?: number;       // Min: 0
}
```

**Files** (optional - if provided, replaces the old file in S3):

- `episodeFile`: Video file (max 5GB, optional) - replaces old episode video
- `thumbnail`: Thumbnail image file (optional) - replaces old thumbnail

**Response**:

```typescript
{
  message: string; // "Episode updated successfully"
  episode: Episode; // Updated episode object
}
```

**Note**: When a new file is uploaded, the old file is automatically deleted from S3.

---

### DELETE `/episode/:id`

**Description**: Delete an episode  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // Deletion confirmation message
}
```

---

## 7. Reels Controller (`/reels`)

### POST `/reels`

**Description**: Upload a new reel with video and thumbnail  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN`, `SUPERADMIN`, or `DEVELOPER`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateReelDto`):

```typescript
{
  title: string;      // 2-100 characters (required)
  projectId: string;  // Valid MongoDB ObjectId (required)
}
```

**Files**:

- `file`: Video file (max 5GB, required)
  - Field name: `file`
  - Max count: 1
- `thumbnail`: Thumbnail image file (required)
  - Field name: `thumbnail`
  - Max count: 1

**Response**:

```typescript
{
  message: string; // "Reel uploaded successfully"
  reel: {
    _id: string;
    title: string;
    videoUrl: string;           // S3 CloudFront URL
    thumbnail: string;          // S3 CloudFront URL
    projectId: string;          // MongoDB ObjectId
    developerId: string;        // MongoDB ObjectId (auto-populated from JWT)
    viewCount: number;          // Default: 0
    saveCount: number;          // Default: 0
    s3Key: string;              // S3 object key for video
    createdAt: Date;
    updatedAt: Date;
  }
}
```

**Error Responses**:

- `400 Bad Request`: "Video file is required"
- `400 Bad Request`: "Thumbnail file is required"

---

### GET `/reels`

**Description**: Get all reels  
**Authentication**: None  
**Request**: None  
**Response**: 

```typescript
Array<{
  _id: string;
  title: string;
  videoUrl: string;           // S3 CloudFront URL
  thumbnail: string;          // S3 CloudFront URL
  projectId: string | Project; // May be populated
  developerId: string | Developer; // May be populated
  viewCount: number;
  saveCount: number;
  s3Key: string;
  createdAt: Date;
  updatedAt: Date;
}>
```

---

### GET `/reels/saved`

**Description**: Get all reels saved by the current user  
**Authentication**: Required (`JwtAuthGuard`)  
**Required Role**: Any authenticated user  
**Request**: None  
**Note**: User ID is extracted from JWT token (`req.user.sub`)

**Response**:

```typescript
{
  message: string; // "Saved reels fetched successfully"
  reels: Array<{
    _id: string;
    title: string;
    videoUrl: string;
    thumbnail: string;
    projectId: string | Project;
    developerId: string | Developer;
    viewCount: number;
    saveCount: number;
  }>;
}
```

---

### GET `/reels/:id`

**Description**: Get a single reel by ID  
**Authentication**: None  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: 

```typescript
{
  _id: string;
  title: string;
  videoUrl: string;           // S3 CloudFront URL
  thumbnail: string;          // S3 CloudFront URL
  projectId: string | Project; // May be populated
  developerId: string | Developer; // May be populated
  viewCount: number;
  saveCount: number;
  s3Key: string;
  createdAt: Date;
  updatedAt: Date;
}
```

---

### PATCH `/reels/:id`

**Description**: Update a reel (supports updating metadata and/or replacing video/thumbnail files)  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN`, `SUPERADMIN`, or `DEVELOPER`  
**Request Type**: `multipart/form-data`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateReelDto` - all fields optional):

```typescript
{
  title?: string;      // 2-100 characters (optional)
  projectId?: string;  // Valid MongoDB ObjectId (optional)
}
```

**Files** (all optional):

- `file`: Video file (max 5GB, optional)
  - If provided, replaces the existing video file in S3
  - Field name: `file`
  - Max count: 1
- `thumbnail`: Thumbnail image file (optional)
  - If provided, replaces the existing thumbnail in S3
  - Field name: `thumbnail`
  - Max count: 1

**Response**: 

```typescript
{
  message: string; // "Reel updated successfully"
  reel: {
    _id: string;
    title: string;
    videoUrl: string;           // Updated S3 CloudFront URL (if file was replaced)
    thumbnail: string;          // Updated S3 CloudFront URL (if thumbnail was replaced)
    projectId: string;
    developerId: string;
    viewCount: number;
    saveCount: number;
    s3Key: string;              // Updated S3 key (if file was replaced)
    createdAt: Date;
    updatedAt: Date;
  }
}
```

**Note**: When new files are uploaded, old files are automatically deleted from S3.

---

### DELETE `/reels/:id`

**Description**: Delete a reel (removes from database and deletes files from S3)  
**Authentication**: Required (`JwtAuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN`, `SUPERADMIN`, or `DEVELOPER`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**:

```typescript
{
  message: string; // "Reel deleted successfully"
}
```

**Note**: Both the video file and thumbnail are automatically deleted from S3.

---

### POST `/reels/:id/save`

**Description**: Save a reel to the current user's saved reels collection  
**Authentication**: Required (`JwtAuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Note**: User ID is extracted from JWT token (`req.user.sub`)

**Response**:

```typescript
{
  message: string; // "Reel saved successfully"
  reel: {
    _id: string;
    saveCount: number; // Incremented by 1
    // ... other reel fields
  }
}
```

---

### POST `/reels/:id/unsave`

**Description**: Remove a reel from the current user's saved reels collection  
**Authentication**: Required (`JwtAuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Note**: User ID is extracted from JWT token (`req.user.sub`)

**Response**:

```typescript
{
  message: string; // "Reel unsaved successfully"
  reel: {
    _id: string;
    saveCount: number; // Decremented by 1
    // ... other reel fields
  }
}
```

---

## 8. S3/Upload Controller (`/upload`)

### POST `/upload`

**Description**: Upload a file to S3  
**Authentication**: None  
**Request Type**: `multipart/form-data`  
**Request Body**:

```typescript
{
  folder?: 'episodes' | 'reels' | 'images' | 'PDF';  // Optional, defaults to 'images'
}
```

**Files**:

- `file`: File (required)
  - Max size: 100MB
  - Allowed types: jpg, jpeg, png, gif, pdf, mp4, mov, avi, mp3, wav

**Response**:

```typescript
{
  success: true;
  message: 'File uploaded successfully';
  data: {
    key: string; // S3 object key
    url: string; // CloudFront URL
  }
}
```

---

### POST `/upload/episode`

**Description**: Upload an episode video file to S3  
**Authentication**: None  
**Request Type**: `multipart/form-data`  
**Files**:

- `file`: Video file (required)
  - Max size: 500MB
  - Allowed types: mp4, mov, avi, mkv

**Response**:

```typescript
{
  success: true;
  message: 'Episode uploaded successfully';
  data: {
    key: string; // S3 object key (in episodes folder)
    url: string; // CloudFront URL
  }
}
```

---

### POST `/upload/reel`

**Description**: Upload a reel video file to S3  
**Authentication**: None  
**Request Type**: `multipart/form-data`  
**Files**:

- `file`: Video file (required)
  - Max size: 100MB
  - Allowed types: mp4, mov

**Response**:

```typescript
{
  success: true;
  message: 'Reel uploaded successfully';
  data: {
    key: string; // S3 object key (in reels folder)
    url: string; // CloudFront URL
  }
}
```

---

### POST `/upload/image`

**Description**: Upload an image file to S3  
**Authentication**: None  
**Request Type**: `multipart/form-data`  
**Files**:

- `file`: Image file (required)
  - Max size: 10MB
  - Allowed types: jpg, jpeg, png, gif, webp

**Response**:

```typescript
{
  success: true;
  message: 'Image uploaded successfully';
  data: {
    key: string; // S3 object key (in images folder)
    url: string; // CloudFront URL
  }
}
```

---

### POST `/upload/pdf`

**Description**: Upload a PDF file to S3  
**Authentication**: None  
**Request Type**: `multipart/form-data`  
**Files**:

- `file`: PDF file (required)
  - Max size: 20MB
  - Allowed types: pdf

**Response**:

```typescript
{
  success: true;
  message: 'PDF uploaded successfully';
  data: {
    key: string; // S3 object key (in PDF folder)
    url: string; // CloudFront URL
  }
}
```

---

## 9. News Controller (`/news`)

### POST `/news`

**Description**: Create a new news item with thumbnail  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateNewsDto`):

```typescript
{
  title: string; // Required
  projectId: string; // MongoDB ObjectId (required)
  developer: string; // Required
}
```

**Files**:

- `image`: Thumbnail image file (required)

**Response**:

```typescript
{
  _id: string;
  title: string;
  thumbnail: string; // S3 CloudFront URL
  projectId: string; // Populated Project object
  developer: string;
  createdAt: Date;
  updatedAt: Date;
}
```

---

### GET `/news`

**Description**: Get all news items  
**Authentication**: None  
**Request**: None  
**Response**: Array of news objects with populated project references

---

### GET `/news/:id`

**Description**: Get a news item by ID  
**Authentication**: None  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: News object with populated project reference

---

### PATCH `/news/:id`

**Description**: Update a news item  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data` (optional file)  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateNewsDto` - all fields optional):

```typescript
{
  title?: string;
  projectId?: string;             // MongoDB ObjectId
  developer?: string;
}
```

**Files**:

- `image`: Thumbnail image file (optional)

**Response**: Updated news object with populated project reference

---

### DELETE `/news/:id`

**Description**: Delete a news item (removes thumbnail from S3)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Deleted news object

---

## 10. Files Controller (`/files`)

### POST `/files/upload/inventory`

**Description**: Upload an inventory file to S3  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreateInventoryDto`):

```typescript
{
  projectId: string; // MongoDB ObjectId (required)
  title: string; // Required
}
```

**Files**:

- `inventory`: Inventory file (required)
  - Supported formats: pdf, xlsx, csv, etc.

**Response**:

```typescript
{
  message: string; // "Inventory uploaded successfully"
  inventory: Inventory; // Created inventory object
}
```

---

### POST `/files/upload/pdf`

**Description**: Upload a PDF file to S3  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Request Body** (`CreatePdfDto`):

```typescript
{
  projectId: string; // MongoDB ObjectId (required)
  title: string; // Required
}
```

**Files**:

- `PDF`: PDF file (required)

**Response**:

```typescript
{
  message: string; // "PDF uploaded successfully"
  pdf: File; // Created PDF object
}
```

---

### GET `/files/inventory`

**Description**: Get all inventory files  
**Authentication**: Required (`AuthGuard`)  
**Required Role**: Any authenticated user  
**Request**: None  
**Response**: Array of inventory objects with populated project references

---

### GET `/files/inventory/:id`

**Description**: Get an inventory file by ID  
**Authentication**: Required (`AuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Inventory object with populated project reference

---

### GET `/files/pdf`

**Description**: Get all PDF files  
**Authentication**: Required (`AuthGuard`)  
**Required Role**: Any authenticated user  
**Request**: None  
**Response**: Array of PDF objects with populated project references

---

### GET `/files/pdf/:id`

**Description**: Get a PDF file by ID  
**Authentication**: Required (`AuthGuard`)  
**Required Role**: Any authenticated user  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: PDF object with populated project reference

---

### PATCH `/files/inventory/:id`

**Description**: Update an inventory file (with optional file replacement)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdateInventoryDto` - all fields optional):

```typescript
{
  title?: string;
}
```

**Files** (optional - if provided, replaces the old file in S3):

- `inventory`: Inventory file (optional) - replaces old inventory file

**Response**:

```typescript
{
  message: string; // "Inventory updated successfully"
  inventory: Inventory; // Updated inventory object with populated project and developer
}
```

**Note**: When a new file is uploaded, the old file is automatically deleted from S3.

---

### PATCH `/files/pdf/:id`

**Description**: Update a PDF file (with optional file replacement)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Request Type**: `multipart/form-data`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Request Body** (`UpdatePdfDto` - all fields optional):

```typescript
{
  title?: string;
}
```

**Files** (optional - if provided, replaces the old file in S3):

- `PDF`: PDF file (optional) - replaces old PDF file

**Response**:

```typescript
{
  message: string; // "PDF updated successfully"
  pdf: File; // Updated PDF object with populated project and developer
}
```

**Note**: When a new file is uploaded, the old file is automatically deleted from S3.

---

### DELETE `/files/inventory/:id`

**Description**: Delete an inventory file (removes from S3)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Deletion confirmation

---

### DELETE `/files/pdf/:id`

**Description**: Delete a PDF file (removes from S3)  
**Authentication**: Required (`AuthGuard`, `RolesGuard`)  
**Required Role**: `ADMIN` or `SUPERADMIN`  
**Route Parameters** (`MongoIdDto`):

```typescript
{
  id: string; // Valid MongoDB ObjectId (required)
}
```

**Response**: Deletion confirmation

---

## 11. Watch History Controller (`/watch-history`)

Tracks user progress for "Continue Watching" and allows resuming playback.

### POST `/watch-history/progress`

**Description**: Create/update watch progress. Automatically calculates `progressPercentage` and marks `completed=true` when progress reaches **90%+**.  
**Authentication**: Required (`JwtAuthGuard`)  
**Request Body** (`UpdateWatchProgressDto`):

```typescript
{
  contentId: string;            // Required (unique per user)
  contentTitle: string;         // Required
  contentThumbnail?: string;    // Optional URL
  currentTime: number;          // Required (seconds, >= 0)
  duration: number;             // Required (seconds, >= 1)
  contentType?: string;         // Optional: 'movie' | 'series' | 'episode'
  season?: number;              // Optional (for series/episodes)
  episode?: number;             // Optional (for series/episodes)
}
```

**Response**:

```typescript
{
  message: string; // "Watch progress updated successfully"
  watchHistory: {
    _id: string;
    userId: string;
    contentId: string;
    contentTitle: string;
    contentThumbnail?: string;
    currentTime: number;
    duration: number;
    progressPercentage: number; // 0-100
    completed: boolean;         // true if progress >= 90
    lastWatchedAt: Date;
    contentType?: string;
    season?: number;
    episode?: number;
    createdAt: Date;
    updatedAt: Date;
  };
}
```

---

### GET `/watch-history/continue-watching?limit=10`

**Description**: Returns incomplete content with progress (`0 < progress < 90`), sorted by most recently watched.  
**Authentication**: Required (`JwtAuthGuard`)  
**Query Parameters**:

- `limit` (optional): default `10` (max 100)

**Response**:

```typescript
{
  message: string; // "Continue watching list fetched successfully"
  items: WatchHistory[];
  count: number;
}
```

---

### GET `/watch-history?includeCompleted=true&limit=50`

**Description**: Returns watch history.  
**Authentication**: Required (`JwtAuthGuard`)  
**Query Parameters**:

- `includeCompleted` (optional): default `true`
- `limit` (optional): default `50` (max 200)

**Response**:

```typescript
{
  message: string; // "Watch history fetched successfully"
  items: WatchHistory[];
  count: number;
}
```

---

### GET `/watch-history/recent?limit=10`

**Description**: Returns content watched in the last 24 hours.  
**Authentication**: Required (`JwtAuthGuard`)  
**Query Parameters**:

- `limit` (optional): default `10` (max 100)

**Response**:

```typescript
{
  message: string; // "Recently watched content fetched successfully"
  items: WatchHistory[];
  count: number;
}
```

---

### GET `/watch-history/content/:contentId`

**Description**: Returns watch progress for a specific content.  
**Authentication**: Required (`JwtAuthGuard`)

**Response**:

```typescript
{
  message: string; // "Watch progress fetched successfully"
  watchHistory: WatchHistory | null;
}
```

---

### POST `/watch-history/content/:contentId/complete`

**Description**: Manually mark content as completed (`progressPercentage=100`).  
**Authentication**: Required (`JwtAuthGuard`)

**Response**:

```typescript
{
  message: string; // "Content marked as completed"
  watchHistory: WatchHistory;
}
```

---

### DELETE `/watch-history/content/:contentId`

**Description**: Remove a specific content from watch history.  
**Authentication**: Required (`JwtAuthGuard`)

**Response**:

```typescript
{
  message: string; // "Content removed from watch history"
}
```

---

### DELETE `/watch-history/clear`

**Description**: Clear all watch history for the current user.  
**Authentication**: Required (`JwtAuthGuard`)

**Response**:

```typescript
{
  message: string; // "Watch history cleared successfully"
}
```

---

## 12. Subscription Controller (`/subscription`)

Handles subscription plan creation, payment checkout with Paymob iframe generation, and secure webhook HMAC verification.

### POST `/subscription/paymob/plan`

**Description**: Create a recurring subscription plan on Paymob  
**Authentication**: Public (`@Public()`)  
**Request Body** (`CreateSubscriptionPlanInput`):

```typescript
{
  name: string;                                           // Required (e.g. "Monthly Premium")
  amount_cents: number;                                   // Required (e.g. 10000 = 100 EGP)
  frequency: number;                                      // Required in days (e.g. 30)
  plan_type?: 'rent' | 'installment' | 'regular' | string; // Optional
  webhook_url?: string;                                   // Optional
  reminder_days?: number | string;                        // Optional
  retrial_days?: number | string;                         // Optional
  number_of_deductions?: number | string;                 // Optional
  use_transaction_amount?: boolean;                       // Optional
  is_active?: boolean;                                    // Optional (default: true)
  integration?: number;                                   // Optional (Paymob integration ID)
  fee?: number | string;                                  // Optional
}
```

**Response**: Paymob plan creation response object containing plan `id`, `name`, `amount_cents`, etc.

---

### GET `/subscription/paymob/plans`

**Description**: Retrieve all registered subscription plans from Paymob  
**Authentication**: Public (`@Public()`)  
**Request**: None  
**Response**: Array of Paymob subscription plan objects

---

### POST `/subscription/paymob/checkout`

**Description**: Initiates checkout, creates a Paymob order and payment key, and generates an embeddable Paymob iframe URL  
**Authentication**: Public (`@Public()`)  
**Request Body**:

```typescript
{
  amountCents: number;            // Required amount in cents (e.g. 5000 = 50.00 EGP)
  merchantOrderId?: string;       // Optional merchant-side reference
  billingData?: {                 // Optional customer billing information
    first_name: string;
    last_name: string;
    email: string;
    phone_number: string;
    apartment?: string;
    floor?: string;
    street?: string;
    building?: string;
    shipping_method?: string;
    postal_code?: string;
    city?: string;
    country?: string;
    state?: string;
  };
}
```

**Response**:

```typescript
{
  orderId: number;                  // Paymob numeric order ID
  merchantOrderId: string;          // Generated unique merchant order identifier
  paymentToken: string;             // Paymob payment key token
  iframeUrl: string;                // Complete URL to embed in web/mobile iframe for card payment
}
```

---

### POST `/subscription/paymob/webhook`

**Description**: Webhook endpoint for Paymob transaction notifications. Verifies the SHA512 HMAC signature using configured `PAYMOB_HMAC_SECRET`.  
**Authentication**: Public (`@Public()`)  
**Query Parameters**:
- `hmac`: string (HMAC SHA512 hash sent by Paymob in query)

**Request Body**: Paymob transaction callback payload object  
**Response**:

```typescript
{
  success: boolean;  // true
  hmacValid: boolean; // true if HMAC matches, false otherwise
}
```

---

### POST `/subscription`

**Description**: Create a new subscription record  
**Authentication**: Required (`JwtAuthGuard`)  
**Request Body** (`CreateSubscriptionDto`)  
**Response**: Subscription record

---

### GET `/subscription`

**Description**: Retrieve all subscriptions  
**Authentication**: Required (`JwtAuthGuard`)  
**Response**: Array of subscription records

---

### GET `/subscription/:id`

**Description**: Retrieve a single subscription by ID  
**Authentication**: Required (`JwtAuthGuard`)  
**Route Parameters**:
- `id`: number

**Response**: Subscription record

---

### PATCH `/subscription/:id`

**Description**: Update a subscription by ID  
**Authentication**: Required (`JwtAuthGuard`)  
**Route Parameters**:
- `id`: number

**Request Body** (`UpdateSubscriptionDto`)  
**Response**: Updated subscription record

---

### DELETE `/subscription/:id`

**Description**: Remove a subscription by ID  
**Authentication**: Required (`JwtAuthGuard`)  
**Route Parameters**:
- `id`: number

**Response**: Deletion confirmation

---

## Response Entities

### User Entity

```typescript
{
  _id: string;
  username: string;
  email: string;
  password: string;                    // Excluded from responses
  phoneNumber: string;
  savedProjects: string[];             // Array of Project ObjectIds
  savedReels: string[];                // Array of Reel ObjectIds
  role: 'user' | 'admin' | 'developer' | 'superadmin';
  isEmailVerified: boolean;            // Email verification status
  emailVerificationOTP?: string;       // Excluded from responses
  emailVerificationOTPExpires?: Date;  // Excluded from responses
  passwordResetOTP?: string;           // Excluded from responses
  passwordResetOTPExpires?: Date;      // Excluded from responses
  createdAt: Date;
  updatedAt: Date;
}
```

### Project Entity

```typescript
{
  _id: string;
  title: string;
  slug: string;
  logoUrl?: string;
  location: string;
  status: 'PLANNING' | 'CONSTRUCTION' | 'COMPLETED' | 'DELIVERED';
  developer: string | Developer;  // ObjectId or populated Developer
  script: string;
  episodes: string[] | Episode[];  // Array of ObjectIds or populated Episodes
  reels: string[] | Reel[];        // Array of ObjectIds or populated Reels
  inventory?: string | Inventory;   // ObjectId or populated Inventory (single)
  pdf: string[] | File[];           // Array of ObjectIds or populated Files
  heroVideoUrl: string;
  whatsappNumber?: string;
  trendingScore: number;
  saveCount: number;
  viewCount: number;
  deletedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}
```

### Developer Entity

```typescript
{
  _id: string;
  name: string;
  logo: string;
  email?: string;
  phone: string;
  location: string;
  projects: string[] | Project[];  // Array of ObjectIds or populated Projects
  deletedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}
```

### Episode Entity

```typescript
{
  _id: string;
  projectId: string | Project;  // ObjectId or populated Project
  title: string;
  thumbnail?: string;
  episodeUrl: string;
  episodeOrder: string;
  duration?: string;
  s3Key: string;
  createdAt: Date;
  updatedAt: Date;
}
```

### Reel Entity

```typescript
{
  _id: string;
  title: string;
  description?: string;
  videoUrl: string;          // S3 URL to video
  thumbnail: string;         // S3 URL to thumbnail
  projectId?: string | Project;  // ObjectId or populated Project
  s3VideoKey: string;        // S3 key for video
  s3ThumbnailKey: string;    // S3 key for thumbnail
  savedBy?: string[];        // Array of User ObjectIds
  createdAt: Date;
  updatedAt: Date;
}
```

### News Entity

```typescript
{
  _id: string;
  title: string;
  thumbnail: string; // S3 CloudFront URL
  projectId: string | Project; // ObjectId or populated Project
  developer: string;
  createdAt: Date;
  updatedAt: Date;
}
```

### Inventory Entity

```typescript
{
  _id: string;
  projectId: string | Project;   // ObjectId or populated Project
  fileUrl: string;               // S3 CloudFront URL
  fileName: string;
  s3Key: string;                 // S3 object key
  description?: string;
  createdAt: Date;
  updatedAt: Date;
}
```

### File Entity (PDF)

```typescript
{
  _id: string;
  projectId: string | Project; // ObjectId or populated Project
  fileUrl: string; // S3 CloudFront URL
  fileName: string;
  title: string;
  s3Key: string; // S3 object key
  createdAt: Date;
  updatedAt: Date;
}
```

### Paymob Checkout Session Entity

```typescript
{
  orderId: number;
  merchantOrderId: string;
  paymentToken: string;
  iframeUrl: string;
}
```

---

## Authentication

Most routes require JWT authentication. Include the token in the Authorization header:

```
Authorization: Bearer <jwt_token>
```

The token is obtained from `/auth/login` or `/auth/register` endpoints.

---

## Error Responses

All endpoints may return standard HTTP error responses:

- `400 Bad Request`: Invalid request data
- `401 Unauthorized`: Missing or invalid authentication token
- `403 Forbidden`: Insufficient permissions (role-based)
- `404 Not Found`: Resource not found
- `409 Conflict`: Resource conflict (e.g., user already exists)
- `500 Internal Server Error`: Server error

---

## Notes

1. All MongoDB ObjectIds must be valid 24-character hexadecimal strings
2. File uploads use `multipart/form-data` content type
3. Query parameters and route parameters are automatically validated
4. Dates are returned in ISO 8601 format
5. Pagination defaults: `limit=10`, `page=1`
6. Some routes marked as "TODO" are not yet fully implemented
