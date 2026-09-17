import { NextResponse } from "next/server";

export function middleware(request) {
  const { pathname } = request.nextUrl;
  const token = request.cookies.get("token")?.value;

  if (!token) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    return NextResponse.redirect(loginUrl);
  }

  try {
    const payloadBase64 = token.split(".")[1];
    const payloadJson = Buffer.from(payloadBase64, "base64").toString("utf-8");
    const payload = JSON.parse(payloadJson);

    if (Date.now() >= payload.exp * 1000) {
      const loginUrl = request.nextUrl.clone();
      loginUrl.pathname = "/login";
      return NextResponse.redirect(loginUrl);
    }

    const userRoles = payload["http://schemas.microsoft.com/ws/2008/06/identity/claims/role"];
    const isAdmin = Array.isArray(userRoles)
    ? userRoles.includes("Admin") || userRoles.includes("SuperAdmin")
    : userRoles === "Admin" || userRoles === "SuperAdmin";
  

    if (isAdmin && pathname === "/tickets") {
      const adminUrl = request.nextUrl.clone();
      adminUrl.pathname = "/admin/tickets";
      return NextResponse.redirect(adminUrl);
    }

    if (!isAdmin && pathname.startsWith("/admin")) {
      const userUrl = request.nextUrl.clone();
      userUrl.pathname = "/tickets";
      return NextResponse.redirect(userUrl);
    }

  } catch (err) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/tickets", "/tickets/:id*", "/admin/:path*"], 
};
